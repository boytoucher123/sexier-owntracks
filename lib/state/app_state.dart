import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../util/format.dart';
import '../util/timeline.dart';

import 'package:latlong2/latlong.dart';

import '../config/server_config.dart';
import '../models/person.dart';
import '../models/settings.dart';
import '../screens/photo_crop_screen.dart' show kFaceSize;
import '../services/account_service.dart';
import '../services/location_service.dart';
import '../services/mqtt_service.dart';
import '../services/owntracks_protocol.dart';
import '../services/platform_services.dart';
import '../services/recorder_service.dart';
import '../services/settings_store.dart';
import '../strings.dart';

/// The single source of truth the UI listens to.
/// Someone arrived at or left one of the group's places.
class PlaceEvent {
  const PlaceEvent(this.person, this.place, {required this.arrived});
  final Person person;
  final Place place;
  final bool arrived;
}

class AppState extends ChangeNotifier {
  AppState({
    SettingsStore? store,
    MqttService? mqtt,
    LocationService? location,
    RecorderService? recorder,
    AccountService? accounts,
  }) : _store = store ?? SettingsStore(),
       mqtt = mqtt ?? MqttService(),
       location = location ?? LocationService(),
       _recorder = recorder ?? RecorderService(),
       accounts = accounts ?? AccountService();

  final SettingsStore _store;
  final MqttService mqtt;
  final LocationService location;
  final RecorderService _recorder;
  final AccountService accounts;

  /// Your groups and who you can see, from the server. Null until loaded.
  Account? _account;
  Account? get account => _account;
  String? _accountError;
  String? get accountError => _accountError;
  Timer? _poll;

  /// Cards (name, photo) by username, including people asking to join a
  /// group you lead, who aren't on the map.
  final Map<String, CardInfo> _cards = {};
  CardInfo? cardFor(String username) => _cards[username];

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Uint8List? _myFace;
  Uint8List? get myFace => _myFace;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Whether this build has a Google Maps key.
  bool _googleMaps = false;
  bool get googleMapsAvailable => _googleMaps;

  /// The map actually shown: Google Maps unless this build can't use it.
  MapProvider get mapProvider =>
      _googleMaps ? _settings.mapProvider : MapProvider.standard;

  String _clientSuffix = '';

  final Map<String, Person> _people = {};
  StreamSubscription<IncomingMessage>? _msgSub;

  /// Everyone we know about. You first, then most recently seen.
  List<Person> get people {
    final list = _people.values.toList();
    list.sort((a, b) {
      if (isMe(a)) return -1;
      if (isMe(b)) return 1;
      final at = a.last?.timestamp;
      final bt = b.last?.timestamp;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  bool isMe(Person p) => p.topic == _ownTopic;

  String get _ownTopic => (connection ?? _settings).ownTopic;

  // --------------------------------------------------------------- groups ---

  /// The group whose settings (server, tracking) this phone uses.
  Group? get activeGroup {
    final gs = _account?.groups ?? const <Group>[];
    return gs.where((g) => g.id == _settings.activeGroupId).firstOrNull ??
        gs.firstOrNull;
  }

  /// The active group is on its leader's own server (not this app's).
  bool get onOwnServer => activeGroup?.config?.standard == false;

  /// What this phone actually connects with: your account, on the active
  /// group's server, with the group's tracking mode. Null when there's
  /// nothing to connect to yet (no group, or the group isn't set up).
  AppSettings? get connection {
    final s = _settings;
    if (!s.hasAccount) return null;
    final c = activeGroup?.config;
    if (c == null) return null;
    if (c.standard) {
      // The group runs on the server your account is on: its details come
      // from the server, and you use your own login.
      if (c.host.isEmpty) return null;
      return s.copyWith(
        host: c.host,
        port: c.port,
        useTls: c.tls,
        useWebSocket: false,
        baseTopic: c.topicPrefix,
        deviceName: kDeviceName,
        recorderUrl: c.recorderUrl,
        recorderUsername: '',
        recorderPassword: '',
        caPem: c.ca,
        allowUntrustedCertificates: false,
        trackingMode: s.myTracking ?? c.trackingMode,
      );
    }
    // The leader's own server: still your own login (there's no shared
    // group login), so everyone is owntracks/<username>/phone.
    return s.copyWith(
      host: c.host,
      port: c.port,
      useTls: c.tls,
      useWebSocket: false,
      baseTopic: c.topicPrefix,
      deviceName: kDeviceName,
      recorderUrl: c.recorderUrl,
      recorderUsername: '',
      recorderPassword: '',
      caPem: c.ca,
      allowUntrustedCertificates: false,
      trackingMode: s.myTracking ?? c.trackingMode,
    );
  }

  /// Whether someone on the current server belongs on your map.
  bool _allowed(String user, String device) {
    final c = connection;
    if (c == null) return false;
    final g = activeGroup;
    return user == _settings.username || g == null || g.hasMember(user);
  }

  String? _accountNameFor(Person p) {
    if (isMe(p)) return _account?.name;
    final g = activeGroup;
    if (g == null) return null;
    return g.memberName(p.user);
  }

  Person? personByTopic(String topic) => _people[topic];

  String get clientId {
    final dev = _settings.deviceName.isEmpty ? 'phone' : _settings.deviceName;
    return 'flock-$dev-$_clientSuffix';
  }

  Future<void> init() async {
    _settings = await _store.load();
    // Set up with the old shared login: go through setup again to make an
    // account. Name, initials and photo are kept.
    if (_settings.setupComplete && !_settings.hasAccount) {
      _settings = _settings.copyWith(setupComplete: false);
    }
    _myFace = await _store.loadFace();
    _outbox.addAll(await _store.loadOutbox());
    _clientSuffix = await _store.clientIdSuffix();
    // Last known groups, so the phone can connect before the server answers.
    final cached = _settings.hasAccount ? await _store.loadAccount() : null;
    if (cached != null) _account = Account.fromJson(cached);
    _googleMaps = await MapAvailability.googleMapsAvailable();

    mqtt.onConnected = _onConnected;
    mqtt.status.addListener(notifyListeners);
    _msgSub = mqtt.messages.listen(_onMessage);
    location.onFix = _publishFix;

    _loaded = true;
    notifyListeners();

    if (_settings.setupComplete && _settings.hasAccount) {
      unawaited(_applyConnection(force: true));
      _startPolling();
    }
  }

  String? _appliedKey;
  TrackingMode? _trackingApplied;
  bool _trackingKnown = false;

  static String _keyOf(AppSettings? c) => c == null
      ? 'none'
      : [
          c.host,
          c.port,
          c.useTls,
          c.username,
          c.password,
          c.baseTopic,
          c.deviceName,
          c.caPem.hashCode,
          c.keepAliveSeconds,
        ].join('|');

  /// Connects to the active group's server, or disconnects when there's
  /// none. Does nothing if that's already the case, apart from picking up
  /// a new tracking mode.
  Future<void> _applyConnection({bool force = false}) async {
    if (!_settings.setupComplete) return;
    final c = connection;
    final key = _keyOf(c);
    if (!force && key == _appliedKey) {
      await _applyTracking();
      return;
    }
    _appliedKey = key;
    _people.clear();
    notifyListeners();
    if (c == null) {
      await mqtt.disconnect();
    } else {
      await mqtt.connect(c, clientId: clientId);
    }
    await _applyTracking(force: true);
  }

  /// Tracking: your own choice, else the active group's default.
  Future<void> _applyTracking({bool force = false}) async {
    final c = connection;
    final want = c != null && _settings.sharingLocation ? c.trackingMode : null;
    if (!force && _trackingKnown && want == _trackingApplied) return;
    _trackingKnown = true;
    _trackingApplied = want;
    if (want == null) {
      await location.stop();
    } else {
      await location.start(want);
    }
  }

  /// Call when the app returns to the foreground.
  void onResume() {
    if (!_settings.setupComplete || !_settings.hasAccount) return;
    unawaited(mqtt.retryNow());
    _startPolling();
  }

  /// Call when the app goes to the background.
  void onPause() {
    _poll?.cancel();
    _poll = null;
  }

  void _startPolling() {
    unawaited(refreshAccount());
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refreshAccount()),
    );
  }

  void _onConnected() {
    _flushOutbox();
    _publishCard();
    if (_settings.sharingLocation) {
      unawaited(location.reportNow('u'));
    }
  }

  // ---------------------------------------------------------------- setup ---

  Future<ConnectionTestResult> testConnection(AppSettings candidate) {
    return MqttService.testAndDiagnose(candidate, clientId: clientId);
  }

  Future<void> updateSettings(
    AppSettings next, {
    bool reconnect = false,
  }) async {
    final prev = _settings;
    _settings = next;
    await _store.save(next);
    notifyListeners();

    // Renamed yourself: tell the server too (your username stays the same).
    if (prev.displayName != next.displayName &&
        prev.username == next.username &&
        next.hasAccount &&
        next.displayName.trim().isNotEmpty) {
      unawaited(_act(() => accounts.rename(next, next.displayName.trim())));
    }

    if (!next.setupComplete) return;

    // Server and tracking come from the active group; this reconnects only
    // if they changed (or when asked to).
    await _applyConnection(force: reconnect);

    if (prev.displayName != next.displayName ||
        prev.trackerId != next.trackerId) {
      _publishCard();
    }
  }

  /// An invite link that opened the app, waiting to be used in the join form.
  String? pendingInvite;

  /// Called when a `flock://…/join/…` (or https invite) link opens the app.
  void offerInvite(String link) {
    if (Invite.parse(link) == null) return;
    pendingInvite = link;
    notifyListeners();
  }

  /// Use another of your groups' settings (and see its people).
  Future<void> setActiveGroup(Group g) async {
    if (g.id == activeGroup?.id) return;
    await updateSettings(_settings.copyWith(activeGroupId: g.id));
    // Same server: the connection stays up, so swap whose map this is.
    _people.removeWhere((_, p) => !isMe(p) && !_allowed(p.user, p.device));
    for (final p in _people.values) {
      p.accountName = _accountNameFor(p);
    }
    notifyListeners();
    mqtt.refreshPeople();
  }

  /// Your own tracking level; null goes back to the group's default.
  Future<void> setMyTracking(TrackingMode? mode) => updateSettings(
    mode == null
        ? _settings.copyWith(groupDefaultTracking: true)
        : _settings.copyWith(myTracking: mode),
  );

  /// The default the active group's leader picked.
  TrackingMode? get groupTracking => activeGroup?.config?.trackingMode;

  Future<void> completeSetup() async {
    await updateSettings(
      _settings.copyWith(setupComplete: true),
      reconnect: true,
    );
    _startPolling();
  }

  /// Forget everything and go back to the welcome screen.
  Future<void> signOut() async {
    onPause();
    await location.stop();
    await mqtt.disconnect();
    await _store.clearAll();
    _people.clear();
    _cards.clear();
    _account = null;
    _accountError = null;
    _appliedKey = null;
    _trackingKnown = false;
    _myFace = null;
    _settings = const AppSettings();
    notifyListeners();
  }

  // -------------------------------------------------------------- account ---

  /// Joins a group from an invite (pasted text containing
  /// `flock://host:port/join/CODE?ca=…`). The first time, this is also how
  /// the app learns about the server and makes your account there, from
  /// your name. A bare code works for a group on the server you're already
  /// on. Returns an error message, or null when it worked.
  Future<String?> joinWithInvite(String text) async {
    final invite = Invite.parse(text);
    if (invite == null) {
      final code = text.trim();
      if (_settings.hasAccount &&
          RegExp(r'^[A-Za-z0-9]{3}-?[A-Za-z0-9]{3}$').hasMatch(code)) {
        return joinGroup(code);
      }
      return Txt.thatIsnTAnInvite;
    }
    if (_settings.hasAccount && _settings.accountServer != invite.server) {
      return Txt.thisInviteIsForA;
    }
    try {
      final ca = _settings.hasAccount
          ? _settings.accountCa
          : await accounts.trustFor(invite);
      var at = _settings.copyWith(accountServer: invite.server, accountCa: ca);
      Account? joined;
      if (at.username.isNotEmpty && at.password.isNotEmpty) {
        // A login from before (or this server's already): try it first.
        try {
          joined = await accounts.join(at, invite.code);
        } on AccountException catch (e) {
          if (!e.unauthorized) rethrow;
        }
      }
      if (joined == null) {
        final name = _settings.displayName.trim();
        if (name.isEmpty) return Txt.enterYourNameFirst;
        final a = await accounts.signUp(at, name);
        at = at.copyWith(
          username: a.username,
          password: a.password,
          deviceName: kDeviceName,
          displayName: a.name,
          trackerId: _settings.trackerId.isEmpty
              ? trackerIdFromDisplayName(a.name)
              : null,
        );
        _people.clear();
        _cards.clear();
        _account = null;
        joined = await accounts.join(at, invite.code);
      }
      await updateSettings(at);
      _setAccount(joined);
      if (_settings.setupComplete) _startPolling();
      if (pendingInvite != null) {
        pendingInvite = null;
        notifyListeners();
      }
      return null;
    } on AccountException catch (e) {
      return e.message;
    }
  }

  Future<void> refreshAccount() async {
    if (!_settings.hasAccount) return;
    try {
      _setAccount(await accounts.me(_settings));
      _accountError = null;
    } on AccountException catch (e) {
      _accountError = e.message;
      notifyListeners();
    }
  }

  void _setAccount(Account a) {
    final before = {...?_account?.visible.keys, ...?_account?.requesters};
    _account = a;
    unawaited(_store.saveAccount(a.json));
    // Drop anyone who isn't in the active group any more.
    _people.removeWhere((_, p) => !isMe(p) && !_allowed(p.user, p.device));
    for (final p in _people.values) {
      p.accountName = _accountNameFor(p);
    }
    notifyListeners();
    // Someone new: subscribe again so the broker sends their last position.
    final now = {...a.visible.keys, ...a.requesters};
    final someoneNew = now.any((u) => !before.contains(u));
    unawaited(
      _applyConnection().then((_) {
        if (someoneNew) mqtt.refreshPeople();
      }),
    );
  }

  /// Runs a group action and applies the server's answer. Returns an error
  /// message, or null when it worked.
  Future<String?> _act(Future<Account> Function() call) async {
    try {
      _setAccount(await call());
      return null;
    } on AccountException catch (e) {
      return e.message;
    }
  }

  Future<String?> createGroup(String name) =>
      _act(() => accounts.createGroup(_settings, name.trim()));
  Future<String?> joinGroup(String code) =>
      _act(() => accounts.join(_settings, code.trim()));
  Future<String?> approve(Group g, JoinRequest r) =>
      _act(() => accounts.approve(_settings, g.id, r.username));
  Future<String?> deny(Group g, JoinRequest r) =>
      _act(() => accounts.deny(_settings, g.id, r.username));
  Future<String?> removeMember(Group g, String username) =>
      _act(() => accounts.remove(_settings, g.id, username));
  Future<String?> leaveGroup(Group g) =>
      _act(() => accounts.remove(_settings, g.id, _settings.username));
  Future<String?> newInviteCode(Group g) =>
      _act(() => accounts.newCode(_settings, g.id));
  Future<String?> renameGroup(Group g, String name) =>
      _act(() => accounts.renameGroup(_settings, g.id, name.trim()));
  Future<String?> makeLeader(Group g, String username) =>
      _act(() => accounts.makeLeader(_settings, g.id, username));

  // -------------------------------------------------------------- places ---

  /// The active group's shared places.
  List<Place> get places => activeGroup?.places ?? const [];

  /// The shared place [p] is in, if any.
  Place? placeFor(LatLng p) => placeAt(places, p);

  final _placeEvents = StreamController<PlaceEvent>.broadcast();

  /// Someone arriving at or leaving one of the group's places.
  Stream<PlaceEvent> get placeEvents => _placeEvents.stream;

  void _checkPlaces(Person p, LocationFix before, LocationFix now) {
    // Only fresh news: not old positions arriving after a reconnect.
    if (DateTime.now().difference(now.timestamp) >
        const Duration(minutes: 10)) {
      return;
    }
    final was = placeFor(before.latLng);
    final isAt = placeFor(now.latLng);
    if (was?.id == isAt?.id) return;
    if (was != null) _placeEvents.add(PlaceEvent(p, was, arrived: false));
    if (isAt != null) _placeEvents.add(PlaceEvent(p, isAt, arrived: true));
  }

  Future<String?> addPlace(
    Group g, {
    required String name,
    required LatLng at,
    required double radius,
  }) => _act(
    () =>
        accounts.addPlace(_settings, g.id, name: name, at: at, radius: radius),
  );

  Future<String?> removePlace(Group g, Place place) =>
      _act(() => accounts.removePlace(_settings, g.id, place.id));

  final Map<String, (String, Future<Stay?>)> _stays = {};

  /// Where [p] has been since arriving at their current spot (from today's
  /// history), or null when they're on the move or there's no history.
  /// Cached until their location changes.
  Future<Stay?> currentStay(Person p) {
    final last = p.last;
    if (last == null) return Future.value();
    final key =
        '${last.timestamp.millisecondsSinceEpoch}|${last.lat}|${last.lon}';
    final have = _stays[p.topic];
    if (have != null && have.$1 == key) return have.$2;
    final f = () async {
      try {
        final now = DateTime.now();
        final fixes = await history(
          p,
          now.subtract(const Duration(hours: 24)),
          now,
        );
        final all = [
          ...fixes,
          if (fixes.isEmpty || fixes.last.timestamp.isBefore(last.timestamp))
            last,
        ];
        final tl = buildTimeline(all);
        final stay = tl.isEmpty ? null : tl.last;
        if (stay is! Stay) return null;
        if (metersBetween(stay.center, last.latLng) > 150) return null;
        return stay;
      } on Object {
        return null;
      }
    }();
    _stays[p.topic] = (key, f);
    return f;
  }

  /// Leader: how often everyone in the group reports their location.
  Future<String?> setGroupTracking(Group g, TrackingMode mode) => _act(
    () => accounts.setConfig(_settings, g.id, {'tracking_mode': mode.name}),
  );

  /// Leader: put the group on your own server (members get it automatically).
  Future<String?> setGroupServer(Group g, GroupConfig c) =>
      _act(() => accounts.setConfig(_settings, g.id, c.toServerJson()));

  /// Checks a group server's details by logging in with your own account,
  /// before saving them.
  Future<ConnectionTestResult> testGroupServer(GroupConfig c) =>
      MqttService.test(
        _settings.copyWith(
          host: c.host,
          port: c.port,
          useTls: c.tls,
          useWebSocket: false,
          baseTopic: c.topicPrefix,
          deviceName: kDeviceName,
          caPem: c.ca,
          allowUntrustedCertificates: false,
        ),
        clientId: '$clientId-test',
      );

  /// Deletes your account on the server, then signs out.
  Future<String?> deleteAccount() async {
    try {
      await accounts.deleteAccount(_settings);
    } on AccountException catch (e) {
      if (!e.unauthorized) return e.message;
    }
    await signOut();
    return null;
  }

  // -------------------------------------------------------------- profile ---

  /// Crops to a square (if it isn't one already), shrinks it to
  /// [kFaceSize] px and stores it as your photo.
  Future<void> setMyPhoto(Uint8List? original) async {
    _myFace = original == null ? null : await compute(_shrinkFace, original);
    await _store.saveFace(_myFace);
    notifyListeners();
    _publishCard();
  }

  void _publishCard() {
    if (connection == null) return;
    final name = _settings.displayName.isNotEmpty
        ? _settings.displayName
        : _settings.username;
    final payload = OwnTracksProtocol.encodeCard(
      name: name,
      trackerId: _settings.trackerId,
      face: _myFace,
    );
    mqtt.publish('$_ownTopic/info', payload);

    // Reflect it locally straight away.
    final me = _ensurePerson(_ownTopic);
    if (me != null) {
      me.cardName = name;
      me.face = _myFace;
      me.trackerId = _settings.trackerId;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- location ---

  void _publishFix(DeviceFix f) {
    if (!_settings.sharingLocation || connection == null) return;
    final pos = f.position;
    final payload = OwnTracksProtocol.encodeLocation(
      lat: pos.latitude,
      lon: pos.longitude,
      timestamp: pos.timestamp,
      trackerId: _settings.trackerId,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      speedMetersPerSecond: pos.speed,
      heading: pos.heading,
      battery: f.battery,
      charging: f.charging,
      trigger: f.trigger,
    );
    if (!mqtt.publish(_ownTopic, payload)) _queue(_ownTopic, payload);

    // Update our own dot even if we're offline.
    final me = _ensurePerson(_ownTopic);
    if (me != null) {
      me.trackerId = _settings.trackerId;
      me.last = LocationFix(
        lat: pos.latitude,
        lon: pos.longitude,
        timestamp: pos.timestamp.toLocal(),
        accuracy: pos.accuracy,
        battery: f.battery,
        charging: f.charging,
        velocityKmh: pos.speed.isFinite ? pos.speed * 3.6 : null,
      );
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- offline ---

  /// Reports made while offline. Each carries the time it was taken, so sent
  /// later they land in history at the right moment.
  final List<(String, String)> _outbox = [];
  static const _kOutboxMax = 5000;

  /// How many reports are waiting to be sent.
  int get unsentReports => _outbox.length;

  void _queue(String topic, String payload) {
    _outbox.add((topic, payload));
    if (_outbox.length > _kOutboxMax) {
      _outbox.removeRange(0, _outbox.length - _kOutboxMax);
    }
    unawaited(_store.saveOutbox(List.of(_outbox)));
  }

  /// Back online: send what was saved, oldest first. Not retained, so the
  /// broker keeps your newest position (sent right after) as your last.
  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    var sent = 0;
    for (final (topic, payload) in _outbox) {
      if (topic != _ownTopic) {
        sent++; // another server or login: drop it
        continue;
      }
      if (!mqtt.publish(topic, payload, retain: false)) break;
      sent++;
    }
    _outbox.removeRange(0, sent);
    unawaited(_store.saveOutbox(List.of(_outbox)));
  }

  /// Ask someone's phone to send a fresh location (like Life360's "refresh").
  bool requestUpdate(Person p) {
    if (isMe(p)) {
      unawaited(location.reportNow('u'));
      return true;
    }
    return mqtt.publish(
      '${p.topic}/cmd',
      OwnTracksProtocol.encodeReportLocationCommand(),
      retain: false,
    );
  }

  Future<List<LocationFix>> history(Person p, DateTime from, DateTime to) {
    return _recorder.history(
      connection ?? _settings,
      user: p.user,
      device: p.device,
      from: from,
      to: to,
    );
  }

  // ------------------------------------------------------------- incoming ---

  void _onMessage(IncomingMessage m) {
    final parts = OwnTracksProtocol.parseTopic(
      m.topic,
      baseTopic: (connection ?? _settings).baseTopic,
    );
    if (parts == null) return;

    final json = OwnTracksProtocol.decode(m.payload);

    if (parts.subtopic == 'cmd') {
      if (parts.deviceTopic == _ownTopic &&
          json != null &&
          OwnTracksProtocol.isReportLocationCommand(json) &&
          _settings.sharingLocation) {
        unawaited(location.reportNow('r'));
      }
      return;
    }

    // An empty retained message means the device was removed.
    if (json == null) {
      if (parts.subtopic == null && m.payload.trim().isEmpty) {
        if (_people.remove(parts.deviceTopic) != null) notifyListeners();
      }
      return;
    }

    final mine = parts.deviceTopic == _ownTopic;
    if (parts.subtopic == null) {
      final fix = OwnTracksProtocol.parseLocation(json);
      if (fix == null) return;
      if (!mine && !_allowed(parts.user, parts.device)) return;
      final p = _ensurePerson(parts.deviceTopic, parts: parts)!;
      if (p.last == null || !fix.timestamp.isBefore(p.last!.timestamp)) {
        final before = p.last;
        p.last = fix;
        if (before != null) _checkPlaces(p, before, fix);
      }
      if (fix.trackerId != null && fix.trackerId!.isNotEmpty) {
        p.trackerId = fix.trackerId;
      }
      notifyListeners();
    } else if (parts.subtopic == 'info') {
      final card = OwnTracksProtocol.parseCard(json);
      if (card == null) return;
      _cards[parts.user] = card;
      if (!mine && !_allowed(parts.user, parts.device)) {
        notifyListeners(); // e.g. someone asking to join: card only, no pin
        return;
      }
      final p = _ensurePerson(parts.deviceTopic, parts: parts)!;
      if (isMe(p)) return; // we already know who we are
      p.cardName = card.name;
      p.face = card.face;
      if (card.trackerId != null) p.trackerId = card.trackerId;
      notifyListeners();
    }
  }

  Person? _ensurePerson(String topic, {TopicParts? parts}) {
    final existing = _people[topic];
    if (existing != null) return existing;
    parts ??= OwnTracksProtocol.parseTopic(
      topic,
      baseTopic: (connection ?? _settings).baseTopic,
    );
    if (parts == null) return null;
    final p = _people[topic] = Person(
      topic: topic,
      user: parts.user,
      device: parts.device,
    );
    p.accountName = _accountNameFor(p);
    return p;
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    mqtt.status.removeListener(notifyListeners);
    mqtt.dispose();
    location.stop();
    super.dispose();
  }
}

Uint8List _shrinkFace(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final oriented = img.bakeOrientation(decoded);
  final side = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final square = img.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final small = img.copyResize(
    square,
    width: kFaceSize,
    height: kFaceSize,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(small, quality: 85));
}
