// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flock/models/settings.dart';
import 'package:flock/services/account_service.dart';
import 'package:flock/services/location_service.dart';
import 'package:flock/services/mqtt_service.dart';
import 'package:flock/services/owntracks_protocol.dart';
import 'package:flock/services/settings_store.dart';
import 'package:flock/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What the server's GET /me looks like for a leader with one request.
Map<String, dynamic> meJson({
  List<String> visible = const ['jack-lee'],
  List<String> requests = const ['zoe-obrien'],
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
}

class _Mqtt extends MqttService {
  final _ctl = StreamController<IncomingMessage>.broadcast();
  int refreshes = 0;
  @override
  Stream<IncomingMessage> get messages => _ctl.stream;
  void inject(String topic, String payload) =>
      _ctl.add(IncomingMessage(topic, payload));
  @override
  Future<void> connect(AppSettings s, {required String clientId}) async {}
  @override
  bool publish(String topic, String payload, {bool retain = true}) => true;
  @override
  void refreshPeople() => refreshes++;
  @override
  Future<void> disconnect() async {}
}

class _Location extends LocationService {
  @override
  Future<void> start(TrackingMode mode) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> reportNow(String trigger) async {}
}

class _Accounts extends AccountService {
  Map<String, dynamic> response = meJson();
  String? signedUpAs;
  @override
  Future<NewAccount> signUp(String name) async {
    signedUpAs = name;
    return NewAccount(username: 'maya-chen', password: 'pw' * 12, name: name);
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
        baseUrl: 'https://server/flock/api',
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
      final acct = await svc.signUp('Maya Chen');
      expect((acct.username, acct.password), ('maya-chen', 'secret'));
      expect(seen.first.headers.containsKey('Authorization'), isFalse);

      final me = await svc.me(
        const AppSettings(username: 'maya-chen', password: 'secret'),
      );
      expect(me.name, 'Maya Chen');
      expect(
        seen.last.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('maya-chen:secret'))}',
      );
    });

    test('shows the server\'s own message, and flags a bad login', () async {
      final svc = AccountService(
        baseUrl: 'https://server/flock/api',
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
      const s = AppSettings(username: 'u', password: 'p');
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
        baseUrl: 'https://server/flock/api',
        client: MockClient((_) async => throw const SocketExceptionLike()),
      );
      await expectLater(
        svc.signUp('X'),
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

    test('making an account saves the login and publishes as /phone', () async {
      final err = await app.createAccount('  Maya Chen ');
      expect(err, isNull);
      expect(accounts.signedUpAs, 'Maya Chen');
      expect(store.s.username, 'maya-chen');
      expect(store.s.password, isNotEmpty);
      expect(store.s.ownTopic, 'owntracks/maya-chen/phone');
      expect(store.s.displayName, 'Maya Chen');
      expect(store.s.trackerId, 'MC');
      expect(app.account?.groups.single.name, 'Class of 2024');
    });

    test('a phone on the old shared login goes back through setup', () async {
      store.s = const AppSettings(
        username: 'class_of_2024',
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
      await app.createAccount('Maya Chen');
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
      expect(mqtt.refreshes, before + 1);
    });
  });
}

/// Stands in for a network failure inside MockClient.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
