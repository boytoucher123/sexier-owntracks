import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/person.dart';
import '../models/settings.dart';
import '../services/location_service.dart';
import '../services/mqtt_service.dart';
import '../services/owntracks_protocol.dart';
import '../services/recorder_service.dart';
import '../services/settings_store.dart';

/// The single source of truth the UI listens to.
class AppState extends ChangeNotifier {
  AppState({
    SettingsStore? store,
    MqttService? mqtt,
    LocationService? location,
    RecorderService? recorder,
  }) : _store = store ?? SettingsStore(),
       mqtt = mqtt ?? MqttService(),
       location = location ?? LocationService(),
       _recorder = recorder ?? RecorderService();

  final SettingsStore _store;
  final MqttService mqtt;
  final LocationService location;
  final RecorderService _recorder;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Uint8List? _myFace;
  Uint8List? get myFace => _myFace;

  bool _loaded = false;
  bool get loaded => _loaded;

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

  bool isMe(Person p) => p.topic == _settings.ownTopic;

  Person? personByTopic(String topic) => _people[topic];

  String get clientId {
    final dev = _settings.deviceName.isEmpty ? 'phone' : _settings.deviceName;
    return 'flock-$dev-$_clientSuffix';
  }

  Future<void> init() async {
    _settings = await _store.load();
    _myFace = await _store.loadFace();
    _clientSuffix = await _store.clientIdSuffix();

    mqtt.onConnected = _onConnected;
    mqtt.status.addListener(notifyListeners);
    _msgSub = mqtt.messages.listen(_onMessage);
    location.onFix = _publishFix;

    _loaded = true;
    notifyListeners();

    if (_settings.setupComplete) {
      unawaited(_goOnline());
    }
  }

  Future<void> _goOnline() async {
    await mqtt.connect(_settings, clientId: clientId);
    if (_settings.sharingLocation) {
      await location.start(_settings.trackingMode);
    }
  }

  /// Call when the app returns to the foreground.
  void onResume() {
    if (!_settings.setupComplete) return;
    unawaited(mqtt.retryNow());
  }

  void _onConnected() {
    _publishCard();
    if (_settings.sharingLocation) {
      unawaited(location.reportNow('u'));
    }
  }

  // ---------------------------------------------------------------- setup ---

  Future<ConnectionTestResult> testConnection(AppSettings candidate) {
    return MqttService.test(candidate, clientId: clientId);
  }

  Future<void> updateSettings(
    AppSettings next, {
    bool reconnect = false,
  }) async {
    final prev = _settings;
    _settings = next;
    await _store.save(next);
    notifyListeners();

    if (!next.setupComplete) return;

    final connectionChanged =
        reconnect ||
        prev.host != next.host ||
        prev.port != next.port ||
        prev.useTls != next.useTls ||
        prev.useWebSocket != next.useWebSocket ||
        prev.username != next.username ||
        prev.password != next.password ||
        prev.deviceName != next.deviceName ||
        prev.baseTopic != next.baseTopic ||
        prev.keepAliveSeconds != next.keepAliveSeconds ||
        prev.allowUntrustedCertificates != next.allowUntrustedCertificates;

    if (connectionChanged) {
      if (prev.deviceName != next.deviceName) {
        _people.remove(prev.ownTopic);
      }
      await _goOnline();
      return;
    }

    if (prev.displayName != next.displayName ||
        prev.trackerId != next.trackerId) {
      _publishCard();
    }

    if (prev.sharingLocation != next.sharingLocation ||
        prev.trackingMode != next.trackingMode) {
      if (next.sharingLocation) {
        await location.start(next.trackingMode);
      } else {
        await location.stop();
      }
    }
  }

  Future<void> completeSetup() async {
    await updateSettings(
      _settings.copyWith(setupComplete: true),
      reconnect: true,
    );
  }

  /// Forget everything and go back to the welcome screen.
  Future<void> signOut() async {
    await location.stop();
    await mqtt.disconnect();
    await _store.clearAll();
    _people.clear();
    _myFace = null;
    _settings = const AppSettings();
    notifyListeners();
  }

  // -------------------------------------------------------------- profile ---

  /// Crops to a square, shrinks to 160 px and stores it as your photo.
  Future<void> setMyPhoto(Uint8List? original) async {
    _myFace = original == null ? null : await compute(_shrinkFace, original);
    await _store.saveFace(_myFace);
    notifyListeners();
    _publishCard();
  }

  void _publishCard() {
    if (_settings.deviceName.isEmpty) return;
    final name = _settings.displayName.isNotEmpty
        ? _settings.displayName
        : _settings.deviceName;
    final payload = OwnTracksProtocol.encodeCard(
      name: name,
      trackerId: _settings.trackerId,
      face: _myFace,
    );
    mqtt.publish('${_settings.ownTopic}/info', payload);

    // Reflect it locally straight away.
    final me = _ensurePerson(_settings.ownTopic);
    if (me != null) {
      me.cardName = name;
      me.face = _myFace;
      me.trackerId = _settings.trackerId;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- location ---

  void _publishFix(DeviceFix f) {
    if (!_settings.sharingLocation || _settings.deviceName.isEmpty) return;
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
    mqtt.publish(_settings.ownTopic, payload);

    // Update our own dot even if we're offline.
    final me = _ensurePerson(_settings.ownTopic);
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
      _settings,
      user: p.user,
      device: p.device,
      from: from,
      to: to,
    );
  }

  /// Used by setup to check the Recorder address before saving it.
  Future<String?> testRecorder(AppSettings candidate) async {
    try {
      await _recorder.history(
        candidate,
        user: candidate.username,
        device: candidate.deviceName.isEmpty ? 'test' : candidate.deviceName,
        from: DateTime.now().subtract(const Duration(hours: 1)),
      );
      return null;
    } on RecorderException catch (e) {
      return e.message;
    }
  }

  // ------------------------------------------------------------- incoming ---

  void _onMessage(IncomingMessage m) {
    final parts = OwnTracksProtocol.parseTopic(
      m.topic,
      baseTopic: _settings.baseTopic,
    );
    if (parts == null) return;

    final json = OwnTracksProtocol.decode(m.payload);

    if (parts.subtopic == 'cmd') {
      if (parts.deviceTopic == _settings.ownTopic &&
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

    if (parts.subtopic == null) {
      final fix = OwnTracksProtocol.parseLocation(json);
      if (fix == null) return;
      final p = _ensurePerson(parts.deviceTopic, parts: parts)!;
      if (p.last == null || !fix.timestamp.isBefore(p.last!.timestamp)) {
        p.last = fix;
      }
      if (fix.trackerId != null && fix.trackerId!.isNotEmpty) {
        p.trackerId = fix.trackerId;
      }
      notifyListeners();
    } else if (parts.subtopic == 'info') {
      final card = OwnTracksProtocol.parseCard(json);
      if (card == null) return;
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
      baseTopic: _settings.baseTopic,
    );
    if (parts == null) return null;
    return _people[topic] = Person(
      topic: topic,
      user: parts.user,
      device: parts.device,
    );
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
    width: 160,
    height: 160,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(small, quality: 82));
}
