import 'dart:convert';
import 'dart:typed_data';

import 'package:flock/models/settings.dart';
import 'package:flock/services/owntracks_protocol.dart';
import 'package:flock/services/recorder_service.dart';
import 'package:flock/widgets/connection_form.dart';
import 'package:flock/widgets/family_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('topics', () {
    test('parses a location topic', () {
      final p = OwnTracksProtocol.parseTopic('owntracks/family/Fred')!;
      expect(p.user, 'family');
      expect(p.device, 'Fred');
      expect(p.subtopic, isNull);
      expect(p.deviceTopic, 'owntracks/family/Fred');
    });

    test('parses info and cmd subtopics', () {
      expect(
        OwnTracksProtocol.parseTopic('owntracks/family/Fred/info')!.subtopic,
        'info',
      );
      expect(
        OwnTracksProtocol.parseTopic('owntracks/family/Fred/cmd')!.deviceTopic,
        'owntracks/family/Fred',
      );
    });

    test('rejects other prefixes and short topics', () {
      expect(OwnTracksProtocol.parseTopic('other/family/Fred'), isNull);
      expect(OwnTracksProtocol.parseTopic('owntracks/family'), isNull);
    });

    test('supports multi-level base topics', () {
      final p = OwnTracksProtocol.parseTopic(
        'home/ot/family/Fred',
        baseTopic: 'home/ot',
      )!;
      expect(p.user, 'family');
      expect(p.device, 'Fred');
    });
  });

  group('location', () {
    test('round-trips through encode and parse', () {
      final ts = DateTime.utc(2026, 11, 24, 9, 30);
      final s = OwnTracksProtocol.encodeLocation(
        lat: -33.868812345,
        lon: 151.209312345,
        timestamp: ts,
        trackerId: 'FD',
        accuracy: 12.4,
        speedMetersPerSecond: 10,
        heading: 90.2,
        battery: 77,
        charging: true,
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      expect(j['_type'], 'location');
      expect(j['lat'], -33.868812);
      expect(j['tst'], ts.millisecondsSinceEpoch ~/ 1000);
      expect(j['vel'], 36);
      expect(j['bs'], 2);
      expect(j['acc'], 12);

      final fix = OwnTracksProtocol.parseLocation(j)!;
      expect(fix.lat, closeTo(-33.8688, 1e-4));
      expect(fix.battery, 77);
      expect(fix.charging, isTrue);
      expect(fix.trackerId, 'FD');
      expect(fix.timestamp.toUtc(), ts);
    });

    test('drops NaN and negative values instead of sending junk', () {
      final s = OwnTracksProtocol.encodeLocation(
        lat: 1,
        lon: 2,
        timestamp: DateTime.now(),
        trackerId: 'X',
        accuracy: double.nan,
        speedMetersPerSecond: -1,
        heading: -1,
      );
      final j = jsonDecode(s) as Map<String, dynamic>;
      expect(j.containsKey('acc'), isFalse);
      expect(j.containsKey('vel'), isFalse);
      expect(j.containsKey('cog'), isFalse);
    });

    test('ignores messages that are not locations or are incomplete', () {
      expect(
        OwnTracksProtocol.parseLocation({'_type': 'lwt', 'tst': 1}),
        isNull,
      );
      expect(
        OwnTracksProtocol.parseLocation({'_type': 'location', 'lat': 1}),
        isNull,
      );
    });

    test('decode tolerates junk and empty payloads', () {
      expect(OwnTracksProtocol.decode(''), isNull);
      expect(OwnTracksProtocol.decode('not json'), isNull);
      expect(OwnTracksProtocol.decode('[1,2]'), isNull);
    });
  });

  group('card', () {
    test('round-trips name, initials and photo', () {
      final face = Uint8List.fromList([1, 2, 3, 4]);
      final j = jsonDecode(
        OwnTracksProtocol.encodeCard(
          name: 'Fred Durk',
          trackerId: 'FD',
          face: face,
        ),
      ) as Map<String, dynamic>;
      final c = OwnTracksProtocol.parseCard(j)!;
      expect(c.name, 'Fred Durk');
      expect(c.trackerId, 'FD');
      expect(c.face, face);
    });

    test('bad base64 photo is ignored, not fatal', () {
      final c = OwnTracksProtocol.parseCard({
        '_type': 'card',
        'name': 'A',
        'face': '%%%',
      })!;
      expect(c.face, isNull);
      expect(c.name, 'A');
    });
  });

  test('reportLocation command', () {
    final j = jsonDecode(
      OwnTracksProtocol.encodeReportLocationCommand(),
    ) as Map<String, dynamic>;
    expect(OwnTracksProtocol.isReportLocationCommand(j), isTrue);
  });

  group('names', () {
    test('Fred Durk -> initials FD', () {
      expect(trackerIdFromDisplayName('Fred Durk'), 'FD');
    });

    test('single names and messy input', () {
      expect(trackerIdFromDisplayName('fred'), 'FR');
      expect(trackerIdFromDisplayName('  Mary  Jane  Smith '), 'MS');
      expect(trackerIdFromDisplayName(''), '');
    });

    test('everyone publishes as owntracks/<their username>/phone', () {
      const s = AppSettings(
        username: 'maya-chen',
        password: 'p',
        accountServer: 'flock.example.net:8443',
      );
      expect(s.ownTopic, 'owntracks/maya-chen/phone');
      expect(s.hasAccount, isTrue);
    });

    test('a login without a server is not an account', () {
      expect(
        const AppSettings(username: 'someone', password: 'p').hasAccount,
        isFalse,
      );
      expect(const AppSettings().hasAccount, isFalse);
    });
  });

  group('settings', () {
    test('json round-trip keeps secrets out', () {
      const s = AppSettings(
        host: 'h',
        username: 'u',
        password: 'secret',
        recorderPassword: 'secret2',
        trackingMode: TrackingMode.precise,
        mapProvider: MapProvider.google,
      );
      final raw = s.encode();
      expect(raw.contains('secret'), isFalse);
      final back = AppSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        password: 'secret',
      );
      expect(back.host, 'h');
      expect(back.password, 'secret');
      expect(back.trackingMode, TrackingMode.precise);
      expect(back.mapProvider, MapProvider.google);
    });

    test('nothing about a server is built in', () {
      const s = AppSettings();
      expect(
        (s.host, s.recorderUrl, s.caPem, s.accountServer),
        ('', '', '', ''),
      );
      expect(s.hasRecorder, isFalse);
    });
  });

  group('host input', () {
    test('plain host', () {
      final p = parseHostInput('  mqtt.example.com ');
      expect(p.host, 'mqtt.example.com');
      expect(p.port, isNull);
      expect(p.tls, isNull);
    });

    test('host with port', () {
      final p = parseHostInput('mqtt.example.com:1883');
      expect(p.host, 'mqtt.example.com');
      expect(p.port, 1883);
    });

    test('mqtts and mqtt schemes set TLS', () {
      expect(parseHostInput('mqtts://a.b:8883').tls, isTrue);
      final p = parseHostInput('mqtt://a.b');
      expect(p.tls, isFalse);
      expect(p.host, 'a.b');
    });

    test('websocket URL keeps scheme and path, extracts port', () {
      final p = parseHostInput('wss://a.b:8443/mqtt');
      expect(p.webSocket, isTrue);
      expect(p.tls, isTrue);
      expect(p.port, 8443);
      expect(p.host, 'wss://a.b/mqtt');
    });
  });

  group('recorder', () {
    test('builds locations URL with UTC times', () {
      final uri = RecorderService.buildLocationsUri(
        'tracking.example.com/owntracks/',
        user: 'family',
        device: 'Fred',
        from: DateTime.utc(2026, 11, 23, 13, 0, 5),
        to: DateTime.utc(2026, 11, 24),
      );
      expect(uri.scheme, 'https');
      expect(uri.path, '/owntracks/api/0/locations');
      expect(uri.queryParameters['user'], 'family');
      expect(uri.queryParameters['device'], 'Fred');
      expect(uri.queryParameters['from'], '2026-11-23T13:00:05');
      expect(uri.queryParameters['to'], '2026-11-24T00:00:00');
    });

    test('parses {data: [...]} and sorts oldest first', () {
      final body = jsonEncode({
        'count': 2,
        'data': [
          {'lat': 2.0, 'lon': 2.0, 'tst': 200},
          {'_type': 'location', 'lat': 1.0, 'lon': 1.0, 'tst': 100},
          {'junk': true},
        ],
      });
      final fixes = RecorderService.parseLocationsResponse(body);
      expect(fixes.length, 2);
      expect(fixes.first.lat, 1.0);
    });

    test('parses a bare list', () {
      final fixes = RecorderService.parseLocationsResponse(
        jsonEncode([
          {'lat': 1, 'lon': 1, 'tst': 1},
        ]),
      );
      expect(fixes.length, 1);
    });
  });

  group('map tiles', () {
    test('keyless by default', () {
      expect(cartoTileUrl(dark: false, key: ''), isNot(contains('key=')));
    });
    test('light map carries the CARTO key', () {
      expect(
        cartoTileUrl(dark: false, key: 'abc_1'),
        'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?key=abc_1',
      );
    });
    test('dark map carries the CARTO key too', () {
      expect(
        cartoTileUrl(dark: true, key: 'abc_1'),
        'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png?key=abc_1',
      );
    });
  });
}
