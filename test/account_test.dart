// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flock/models/person.dart';
import 'package:flock/models/settings.dart';
import 'package:flock/services/account_service.dart';
import 'package:flock/services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flock/services/mqtt_service.dart';
import 'package:flock/services/owntracks_protocol.dart';
import 'package:flock/services/recorder_service.dart';
import 'package:flock/services/settings_store.dart';
import 'package:flock/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// A throwaway CA made for these tests, and its fingerprint (same as the
/// server's `ca_fingerprint`).
const testCa = '''-----BEGIN CERTIFICATE-----
MIIBhTCCASugAwIBAgIUNI0gAFAHvvaNCmcE9xbABLn939cwCgYIKoZIzj0EAwIw
GDEWMBQGA1UEAwwNRmxvY2sgVGVzdCBDQTAeFw0yNjExMjYwOTA5MzJaFw0zNjEx
MjMwOTA5MzJaMBgxFjAUBgNVBAMMDUZsb2NrIFRlc3QgQ0EwWTATBgcqhkjOPQIB
BggqhkjOPQMBBwNCAATCvdWQzoTu8CWyiiw4sd9nv4E/e4SC/OOu5B9gRG8XsDhW
mzqgXni8Uz08hffy/viDdzmcHRy0zTDDlBDllJtHo1MwUTAdBgNVHQ4EFgQUsGF3
tV+Jd5mWnYHwsl7arT4qEHMwHwYDVR0jBBgwFoAUsGF3tV+Jd5mWnYHwsl7arT4q
EHMwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBO5ftRUisnysgq
Kio8znxxOgS+FQZ9EDfQ5sG0hethlQIhAK5xjd3X7tKGdY8sbngcYieyZ1Nk8MMT
vx9Wm7ryimu2
-----END CERTIFICATE-----
''';
const testCaFp = '5B9fXa80mdzLAlW9nF7SSQeA5oixRK7JvVXaN_k_mLo';
const standardConfig = {
  'standard': true,
  'tracking_mode': 'balanced',
  'host': 'flock.example.net',
  'port': 8883,
  'tls': true,
  'ca': testCa,
  'recorder_url': 'https://flock.example.net:8443',
  'topic_prefix': 'owntracks',
};
const inviteMessage =
    'Join "Class of 2024" on Flock. Install Flock, then paste this whole '
    'message when it asks for an invite:\n\n'
    'flock://flock.example.net:8443/join/K7Q-2MX?ca=$testCaFp';

/// What the server's GET /me looks like for a leader with one request.
Map<String, dynamic> meJson({
  List<String> visible = const ['jack-lee'],
  List<String> requests = const ['zoe-obrien'],
  Map<String, dynamic>? config = standardConfig,
}) => {
  'username': 'maya-chen',
  'name': 'Maya Chen',
  'created': 1795500000,
  'device': 'phone',
  'groups': [
    {
      'id': 7,
      'name': 'Class of 2024',
      'leader': 'maya-chen',
      'role': 'leader',
      'code': 'K7Q-2MX',
      'config': config,
      'members': [
        {'username': 'maya-chen', 'name': 'Maya Chen', 'leader': true},
        for (final v in visible) {'username': v, 'name': 'Jack Lee'},
      ],
      'requests': [
        for (final r in requests)
          {
            'username': r,
            'name': "Zoë O'Brien",
            'created': 1795600000,
            'requested': 1795600100,
          },
      ],
    },
  ],
  'pending': [
    {'id': 9, 'name': 'Footy', 'leader_name': 'Sam'},
  ],
  'visible': [
    for (final v in visible) {'username': v, 'name': 'Jack Lee'},
  ],
};

class _Store extends SettingsStore {
  AppSettings s = const AppSettings();
  @override
  Future<AppSettings> load() async => s;
  @override
  Future<void> save(AppSettings v) async => s = v;
  @override
  Future<Uint8List?> loadFace() async => null;
  @override
  Future<void> saveFace(Uint8List? b) async {}
  @override
  Future<String> clientIdSuffix() async => 'test1234';
  @override
  Future<void> clearAll() async => s = const AppSettings();

  List<(String, String)> outbox = [];
  @override
  Future<List<(String, String)>> loadOutbox() async => List.of(outbox);
  @override
  Future<void> saveOutbox(List<(String, String)> items) async =>
      outbox = List.of(items);
}

class _Mqtt extends MqttService {
  final _ctl = StreamController<IncomingMessage>.broadcast();
  int refreshes = 0;
  final connects = <AppSettings>[];
  int disconnects = 0;
  @override
  Stream<IncomingMessage> get messages => _ctl.stream;
  void inject(String topic, String payload) =>
      _ctl.add(IncomingMessage(topic, payload));
  @override
  Future<void> connect(AppSettings s, {required String clientId}) async =>
      connects.add(s);
  bool online = true;
  final published = <(String, String, bool)>[]; // topic, payload, retained
  @override
  bool publish(String topic, String payload, {bool retain = true}) {
    if (!online) return false;
    published.add((topic, payload, retain));
    return true;
  }

  void connected() => onConnected?.call();
  @override
  void refreshPeople() => refreshes++;
  @override
  Future<void> disconnect() async => disconnects++;
}

class _Location extends LocationService {
  final modes = <TrackingMode?>[]; // null = stopped
  @override
  Future<void> start(TrackingMode mode) async => modes.add(mode);
  @override
  Future<void> stop() async => modes.add(null);
  @override
  Future<void> reportNow(String trigger) async {}
}

class _Accounts extends AccountService {
  Map<String, dynamic> response = meJson();
  String? signedUpAs;
  String? signedUpAt;
  final joins = <(String, String)>[]; // (username, code)
  bool knowsExistingLogin = true;

  @override
  Future<String> trustFor(Invite invite) async => testCa;

  @override
  Future<NewAccount> signUp(AppSettings at, String name) async {
    signedUpAs = name;
    signedUpAt = at.accountServer;
    return NewAccount(username: 'maya-chen', password: 'pw' * 12, name: name);
  }

  @override
  Future<Account> join(AppSettings s, String code) async {
    if (s.username != 'maya-chen' && !knowsExistingLogin) {
      throw AccountException('Your login wasn\'t accepted.', status: 401);
    }
    joins.add((s.username, code));
    return Account.fromJson(response);
  }

  @override
  Future<Account> me(AppSettings s) async => Account.fromJson(response);
}

String _loc(double lat, double lon) => jsonEncode({
  '_type': 'location',
  'lat': lat,
  'lon': lon,
  'tst': DateTime.now().millisecondsSinceEpoch ~/ 1000,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account.fromJson', () {
    test('reads groups, requests, pending joins and who you can see', () {
      final a = Account.fromJson(meJson());
      expect(a.username, 'maya-chen');
      final g = a.groups.single;
      expect((g.name, g.isLeader, g.code), ('Class of 2024', true, 'K7Q-2MX'));
      expect(g.leaderName, 'Maya Chen');
      expect(g.members.map((m) => m.username), ['maya-chen', 'jack-lee']);
      expect(g.requests.single.name, "Zoë O'Brien");
      expect(a.waitingRequests, 1);
      expect(a.requesters, {'zoe-obrien'});
      expect(a.pending.single.leaderName, 'Sam');
      expect(a.visible, {'jack-lee': 'Jack Lee'});
    });
  });

  group('AccountService', () {
    test('signs up without a login, then uses the account\'s login', () async {
      final seen = <http.BaseRequest>[];
      final svc = AccountService(
        client: MockClient((req) async {
          seen.add(req);
          if (req.url.path.endsWith('/signup')) {
            expect(jsonDecode(req.body), {'name': 'Maya Chen'});
            return http.Response(
              jsonEncode({
                'username': 'maya-chen',
                'password': 'secret',
                'name': 'Maya Chen',
              }),
              201,
            );
          }
          return http.Response(jsonEncode(meJson()), 200);
        }),
      );
      const at = AppSettings(accountServer: 'flock.example.net:8443');
      final acct = await svc.signUp(at, 'Maya Chen');
      expect((acct.username, acct.password), ('maya-chen', 'secret'));
      expect(seen.first.headers.containsKey('Authorization'), isFalse);
      expect(
        seen.first.url.toString(),
        'https://flock.example.net:8443/flock/api/signup',
      );

      final me = await svc.me(
        at.copyWith(username: 'maya-chen', password: 'secret'),
      );
      expect(me.name, 'Maya Chen');
      expect(
        seen.last.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('maya-chen:secret'))}',
      );
    });

    test('shows the server\'s own message, and flags a bad login', () async {
      final svc = AccountService(
        client: MockClient((req) async {
          if (req.url.path.endsWith('/join')) {
            return http.Response(
              jsonEncode({'error': 'No group has that code.'}),
              404,
            );
          }
          return http.Response(jsonEncode({'error': 'Please sign in.'}), 401);
        }),
      );
      const s = AppSettings(username: 'u', password: 'p', accountServer: 'x');
      await expectLater(
        svc.join(s, 'AAA-AAA'),
        throwsA(
          isA<AccountException>()
              .having((e) => e.message, 'message', 'No group has that code.')
              .having((e) => e.unauthorized, 'unauthorized', isFalse),
        ),
      );
      await expectLater(
        svc.me(s),
        throwsA(
          isA<AccountException>().having((e) => e.unauthorized, 'u', true),
        ),
      );
    });

    test('no connection gives a plain message', () async {
      final svc = AccountService(
        client: MockClient((_) async => throw const SocketExceptionLike()),
      );
      await expectLater(
        svc.signUp(const AppSettings(accountServer: 'x'), 'X'),
        throwsA(
          isA<AccountException>().having(
            (e) => e.message,
            'message',
            contains('Couldn\'t reach the server'),
          ),
        ),
      );
    });
  });

  group('invites', () {
    test('found anywhere in a pasted message', () {
      final i = Invite.parse(inviteMessage)!;
      expect(
        (i.server, i.code, i.caFingerprint),
        ('flock.example.net:8443', 'K7Q-2MX', testCaFp),
      );
      expect(Invite.parse('K7Q-2MX'), isNull);
      expect(
        Invite.parse('flock://host.example/join/ABCDEF')!.caFingerprint,
        isNull,
      ); // a server with a public certificate
    });

    test('the web form of the link works too', () {
      final i = Invite.parse(
        'https://flock.example.net:8443/flock/join/K7Q-2MX?ca=$testCaFp',
      )!;
      expect(
        (i.server, i.code, i.caFingerprint),
        ('flock.example.net:8443', 'K7Q-2MX', testCaFp),
      );
    });

    test('the fingerprint matches the server\'s', () {
      expect(caFingerprint(testCa), testCaFp);
    });

    test('the server\'s certificate is only trusted if it matches', () async {
      final good = AccountService(
        client: MockClient(
          (req) async => http.Response(jsonEncode({'pem': testCa}), 200),
        ),
      );
      final i = Invite.parse(inviteMessage)!;
      expect(await good.trustFor(i), testCa);

      final impostor = AccountService(
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({'pem': testCa.replaceFirst('MIIB', 'MIIC')}),
            200,
          ),
        ),
      );
      await expectLater(impostor.trustFor(i), throwsA(isA<AccountException>()));
    });
  });

  group('AppState with accounts', () {
    late _Store store;
    late _Mqtt mqtt;
    late _Accounts accounts;
    late AppState app;

    setUp(() async {
      store = _Store();
      mqtt = _Mqtt();
      accounts = _Accounts();
      app = AppState(
        store: store,
        mqtt: mqtt,
        location: _Location(),
        accounts: accounts,
      );
      await app.init();
    });

    test('the app knows no server until an invite', () {
      expect(const AppSettings().host, '');
      expect(const AppSettings().recorderUrl, '');
      expect(const AppSettings().caPem, '');
      expect(app.connection, isNull);
    });

    test(
      'an invite makes the account on its server, then asks to join',
      () async {
        await app.updateSettings(
          app.settings.copyWith(displayName: ' Maya Chen '),
        );
        final err = await app.joinWithInvite(inviteMessage);
        expect(err, isNull);
        expect(accounts.signedUpAs, 'Maya Chen');
        expect(accounts.signedUpAt, 'flock.example.net:8443');
        expect(accounts.joins.single, ('maya-chen', 'K7Q-2MX'));
        expect(store.s.accountServer, 'flock.example.net:8443');
        expect(store.s.accountCa, testCa);
        expect(store.s.username, 'maya-chen');
        expect(store.s.trackerId, 'MC');
        expect(app.account?.groups.single.name, 'Class of 2024');
      },
    );

    test('a link that opens the app is filled in, then used up', () async {
      app.offerInvite('https://example.com/not-an-invite');
      expect(app.pendingInvite, isNull);
      const link = 'flock://flock.example.net:8443/join/K7Q-2MX?ca=$testCaFp';
      app.offerInvite(link);
      expect(app.pendingInvite, link);
      await app.updateSettings(app.settings.copyWith(displayName: 'Maya Chen'));
      expect(await app.joinWithInvite(app.pendingInvite!), isNull);
      expect(app.pendingInvite, isNull);
    });

    test('not an invite: a plain message', () async {
      final err = await app.joinWithInvite('K7Q-2MX');
      expect(err, contains('isn\'t an invite'));
      expect(accounts.joins, isEmpty);
    });

    test('a login from before is reused on the invite\'s server', () async {
      store.s = const AppSettings(
        username: 'george-gunter',
        password: 'old-pw',
        displayName: 'George',
        setupComplete: true,
      );
      final legacy = AppState(
        store: store,
        mqtt: mqtt,
        location: _Location(),
        accounts: accounts,
      );
      await legacy.init();
      expect(legacy.settings.setupComplete, isFalse); // no server: set up again
      expect(await legacy.joinWithInvite(inviteMessage), isNull);
      expect(accounts.signedUpAs, isNull); // no new account
      expect(accounts.joins.single, ('george-gunter', 'K7Q-2MX'));
      expect(store.s.accountServer, 'flock.example.net:8443');
    });

    test('a phone with no server goes back through setup', () async {
      store.s = const AppSettings(
        username: 'someone',
        password: 'old',
        displayName: 'Maya Chen',
        setupComplete: true,
      );
      final legacy = AppState(
        store: store,
        mqtt: mqtt,
        location: _Location(),
        accounts: accounts,
      );
      await legacy.init();
      expect(legacy.settings.setupComplete, isFalse);
      expect(legacy.settings.displayName, 'Maya Chen');
    });

    test('only group members are people; requesters are just a card', () async {
      await app.updateSettings(app.settings.copyWith(displayName: 'Maya Chen'));
      await app.joinWithInvite(inviteMessage);
      await Future<void>.delayed(Duration.zero);
      mqtt.inject('owntracks/jack-lee/phone', _loc(-33.87, 151.2));
      mqtt.inject(
        'owntracks/zoe-obrien/phone/info',
        OwnTracksProtocol.encodeCard(name: "Zoë O'Brien", trackerId: 'ZO'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(app.people.map((p) => p.user), ['jack-lee']);
      expect(
        app.people.single.name,
        'Jack Lee',
      ); // from the server, no card yet
      expect(app.cardFor('zoe-obrien')?.name, "Zoë O'Brien");

      // Jack leaves the group: he disappears.
      accounts.response = meJson(visible: const [], requests: const []);
      await app.refreshAccount();
      expect(app.people, isEmpty);

      // Someone new is let in: subscribe again to get their last position.
      final before = mqtt.refreshes;
      accounts.response = meJson(visible: const ['jack-lee', 'sam-o']);
      await app.refreshAccount();
      await pumpEventQueue();
      expect(mqtt.refreshes, before + 1);
    });
  });

  test('reports made offline are kept and sent once back online', () async {
    final store = _Store()
      ..s = const AppSettings(
        username: 'maya-chen',
        password: 'mine',
        displayName: 'Maya Chen',
        accountServer: 'flock.example.net:8443',
        setupComplete: true,
      );
    final mqtt = _Mqtt();
    final loc = _Location();
    final app = AppState(
      store: store,
      mqtt: mqtt,
      location: loc,
      accounts: _Accounts(),
    );
    await app.init();
    await app.refreshAccount();
    await Future<void>.delayed(Duration.zero);

    Position at(double lat, int minutesAgo) => Position(
      latitude: lat,
      longitude: 151.2,
      timestamp: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

    mqtt.online = false;
    loc.onFix!(DeviceFix(at(-33.80, 30), 80, false, 't'));
    loc.onFix!(DeviceFix(at(-33.81, 20), 79, false, 't'));
    expect(app.unsentReports, 2);
    expect(store.outbox, hasLength(2)); // survives the app closing

    mqtt.online = true;
    mqtt.connected();
    final mine = mqtt.published
        .where((p) => p.$1 == 'owntracks/maya-chen/phone')
        .toList();
    expect(mine, hasLength(2));
    expect(mine.every((p) => !p.$3), isTrue); // not retained: old news
    expect(jsonDecode(mine.first.$2)['lat'], -33.80); // oldest first
    expect(app.unsentReports, 0);
    expect(store.outbox, isEmpty);
  });

  group('places', () {
    const beach = {
      'id': 3,
      'name': 'Mona Vale Beach',
      'lat': -33.677,
      'lon': 151.31,
      'radius': 150,
      'created_by': 'jack-lee',
    };

    test('read from the group, and found by distance', () {
      final g = Account.fromJson(meJson()..['groups'][0]['places'] = [beach])
          .groups
          .single;
      final p = g.places.single;
      expect(
        (p.name, p.radius, p.createdBy),
        ('Mona Vale Beach', 150, 'jack-lee'),
      );
      expect(
        placeAt(g.places, const LatLng(-33.6775, 151.3102))?.name,
        'Mona Vale Beach',
      );
      expect(placeAt(g.places, const LatLng(-33.70, 151.31)), isNull);
    });

    late _Mqtt mqtt;
    late _Recorder recorder;
    late AppState app;
    Future<void> boot() async {
      final store = _Store()
        ..s = const AppSettings(
          username: 'maya-chen',
          password: 'mine',
          displayName: 'Maya Chen',
          accountServer: 'flock.example.net:8443',
          setupComplete: true,
        );
      mqtt = _Mqtt();
      recorder = _Recorder();
      final me = meJson();
      me['groups'][0]['places'] = [beach];
      app = AppState(
        store: store,
        mqtt: mqtt,
        location: _Location(),
        recorder: recorder,
        accounts: _Accounts()..response = me,
      );
      await app.init();
      await app.refreshAccount();
      await Future<void>.delayed(Duration.zero);
    }

    test('arriving and leaving are announced', () async {
      await boot();
      final events = <String>[];
      final sub = app.placeEvents.listen(
        (e) => events.add(
          '${e.person.user} ${e.arrived ? 'at' : 'left'} ${e.place.name}',
        ),
      );
      mqtt.inject('owntracks/jack-lee/phone', _loc(-33.70, 151.31));
      await Future<void>.delayed(Duration.zero);
      mqtt.inject('owntracks/jack-lee/phone', _loc(-33.677, 151.31));
      await Future<void>.delayed(Duration.zero);
      mqtt.inject(
        'owntracks/jack-lee/phone',
        _loc(-33.6771, 151.3101),
      ); // still there
      await Future<void>.delayed(Duration.zero);
      mqtt.inject('owntracks/jack-lee/phone', _loc(-33.70, 151.31));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, [
        'jack-lee at Mona Vale Beach',
        'jack-lee left Mona Vale Beach',
      ]);
    });

    test(
      '"at X since": from today\'s history, only while still there',
      () async {
        await boot();
        final now = DateTime.now();
        final arrived = now.subtract(const Duration(hours: 3));
        recorder.fixes = [
          LocationFix(
            lat: -33.60,
            lon: 151.30,
            timestamp: arrived.subtract(const Duration(minutes: 30)),
          ),
          for (var m = 0; m <= 180; m += 10)
            LocationFix(
              lat: -33.677,
              lon: 151.31,
              timestamp: arrived.add(Duration(minutes: m)),
            ),
        ];
        mqtt.inject('owntracks/jack-lee/phone', _loc(-33.677, 151.31));
        await Future<void>.delayed(Duration.zero);
        final jack = app.people.single;
        final stay = await app.currentStay(jack);
        expect(stay, isNotNull);
        expect(stay!.start, arrived);
        expect(app.placeFor(stay.center)?.name, 'Mona Vale Beach');

        // Moved on: no longer "at" anywhere.
        mqtt.inject('owntracks/jack-lee/phone', _loc(-33.75, 151.30));
        await Future<void>.delayed(Duration.zero);
        expect(await app.currentStay(jack), isNull);
      },
    );
  });

  group('group settings', () {
    late _Store store;
    late _Mqtt mqtt;
    late _Location loc;
    late _Accounts accounts;
    late AppState app;

    Future<void> boot(Map<String, dynamic>? config) async {
      store = _Store()
        ..s = const AppSettings(
          username: 'maya-chen',
          password: 'mine',
          displayName: 'Maya Chen',
          accountServer: 'flock.example.net:8443',
          setupComplete: true,
        );
      mqtt = _Mqtt();
      loc = _Location();
      accounts = _Accounts()..response = meJson(config: config);
      app = AppState(
        store: store,
        mqtt: mqtt,
        location: loc,
        accounts: accounts,
      );
      await app.init();
      await app.refreshAccount();
      await Future<void>.delayed(Duration.zero);
    }

    test('a standard group uses this server with your own login', () async {
      await boot({...standardConfig, 'tracking_mode': 'precise'});
      final c = app.connection!;
      expect(
        (c.host, c.port, c.username, c.password),
        ('flock.example.net', 8883, 'maya-chen', 'mine'),
      );
      expect(c.ownTopic, 'owntracks/maya-chen/phone');
      expect(mqtt.connects.last.username, 'maya-chen');
      expect(loc.modes.last, TrackingMode.precise); // the leader's choice
    });

    test('a group on its own server: still your own login', () async {
      await boot({
        'standard': false,
        'host': 'mqtt.example.com',
        'port': 1883,
        'tls': false,
        'topic_prefix': 'ot',
        'recorder_url': 'https://mqtt.example.com/rec',
        'tracking_mode': 'batterySaver',
      });
      final c = app.connection!;
      expect(
        (c.host, c.port, c.useTls, c.username, c.password),
        ('mqtt.example.com', 1883, false, 'maya-chen', 'mine'),
      );
      expect(c.ownTopic, 'ot/maya-chen/phone');
      expect(c.recorderUrl, 'https://mqtt.example.com/rec');
      expect(c.caPem, '');
      expect(app.onOwnServer, isTrue);
      expect(loc.modes.last, TrackingMode.batterySaver);

      // Group members show up, named from the group; others don't.
      mqtt.inject('ot/jack-lee/phone', _loc(-33.87, 151.2));
      mqtt.inject('ot/someone-else/phone', _loc(-33.87, 151.2));
      await Future<void>.delayed(Duration.zero);
      expect(app.people.map((p) => p.user), ['jack-lee']);
      expect(app.people.single.name, 'Jack Lee');
    });

    test('a group without a server: nothing to connect to', () async {
      await boot(null);
      expect(app.connection, isNull);
      expect(mqtt.connects, isEmpty);
      expect(loc.modes.last, isNull); // not tracking
    });

    test(
      'the leader changing tracking switches it without reconnecting',
      () async {
        await boot(standardConfig);
        final connects = mqtt.connects.length;
        accounts.response = meJson(
          config: {...standardConfig, 'tracking_mode': 'precise'},
        );
        await app.refreshAccount();
        await Future<void>.delayed(Duration.zero);
        expect(loc.modes.last, TrackingMode.precise);
        expect(mqtt.connects.length, connects);
      },
    );

    test('your own tracking level beats the group default', () async {
      await boot(standardConfig); // group default: balanced
      await app.setMyTracking(TrackingMode.batterySaver);
      expect(loc.modes.last, TrackingMode.batterySaver);
      expect(store.s.myTracking, TrackingMode.batterySaver); // remembered

      // The leader changes the default: you keep yours.
      accounts.response = meJson(
        config: {...standardConfig, 'tracking_mode': 'precise'},
      );
      await app.refreshAccount();
      await Future<void>.delayed(Duration.zero);
      expect(loc.modes.last, TrackingMode.batterySaver);

      // Back to the group's default.
      await app.setMyTracking(null);
      expect(store.s.myTracking, isNull);
      expect(loc.modes.last, TrackingMode.precise);
    });

    test('switching groups on the same server swaps who you see', () async {
      store = _Store()
        ..s = const AppSettings(
          username: 'maya-chen',
          password: 'mine',
          displayName: 'Maya Chen',
          accountServer: 'flock.example.net:8443',
          setupComplete: true,
        );
      mqtt = _Mqtt();
      loc = _Location();
      final two = meJson(visible: const ['jack-lee']);
      (two['groups'] as List).add({
        'id': 8,
        'name': 'Test',
        'leader': 'maya-chen',
        'role': 'leader',
        'code': 'MEA-TAY',
        'config': standardConfig,
        'members': [
          {'username': 'maya-chen', 'name': 'Maya Chen', 'leader': true},
          {'username': 'sam-o', 'name': 'Sam O'},
        ],
        'requests': const [],
      });
      (two['visible'] as List).add({'username': 'sam-o', 'name': 'Sam O'});
      accounts = _Accounts()..response = two;
      app = AppState(
        store: store,
        mqtt: mqtt,
        location: loc,
        accounts: accounts,
      );
      await app.init();
      await app.refreshAccount();
      await Future<void>.delayed(Duration.zero);

      mqtt.inject('owntracks/jack-lee/phone', _loc(-33.87, 151.2));
      mqtt.inject('owntracks/sam-o/phone', _loc(-33.88, 151.2));
      await Future<void>.delayed(Duration.zero);
      expect(app.activeGroup!.name, 'Class of 2024');
      expect(app.people.map((p) => p.user), ['jack-lee']);

      final connects = mqtt.connects.length;
      final refreshes = mqtt.refreshes;
      await app.setActiveGroup(app.account!.groups.last);
      expect(app.activeGroup!.name, 'Test');
      expect(app.people.map((p) => p.user), isNot(contains('jack-lee')));
      expect(mqtt.connects.length, connects); // same server: no reconnect
      expect(mqtt.refreshes, refreshes + 1); // asks again for Test's people
      mqtt.inject('owntracks/sam-o/phone', _loc(-33.88, 151.2));
      await Future<void>.delayed(Duration.zero);
      expect(app.people.map((p) => p.user), ['sam-o']);
    });
  });
}

class _Recorder extends RecorderService {
  List<LocationFix> fixes = const [];
  @override
  Future<List<LocationFix>> history(
    AppSettings s, {
    required String user,
    required String device,
    required DateTime from,
    DateTime? to,
  }) async => fixes;
}

/// Stands in for a network failure inside MockClient.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
