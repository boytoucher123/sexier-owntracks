// End-to-end test against a real MQTT broker.
//
// Skipped unless MQTT_TEST_PORT is set. To run locally:
//   mosquitto with user `family` / password `hunter2` on 127.0.0.1:$MQTT_TEST_PORT
//   MQTT_TEST_PORT=18830 flutter test test/mqtt_integration_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flock/models/settings.dart';
import 'package:flock/services/mqtt_service.dart';
import 'package:flock/services/owntracks_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final portEnv = Platform.environment['MQTT_TEST_PORT'];
  final skip = portEnv == null ? 'set MQTT_TEST_PORT to run' : null;
  final port = int.tryParse(portEnv ?? '') ?? 0;

  AppSettings settingsFor(String device, {String password = 'hunter2'}) =>
      AppSettings(
        host: '127.0.0.1',
        port: port,
        useTls: false,
        username: 'family',
        password: password,
        deviceName: device,
        trackerId: device.substring(0, 2).toUpperCase(),
        setupComplete: true,
      );

  test('test() succeeds with the right login', () async {
    final r = await MqttService.test(settingsFor('Fred'), clientId: 'flock-t1');
    expect(r.success, isTrue, reason: r.message);
  }, skip: skip);

  test('test() explains a wrong password in plain English', () async {
    final r = await MqttService.test(
      settingsFor('Fred', password: 'nope'),
      clientId: 'flock-t2',
    );
    expect(r.success, isFalse);
    expect(r.message, contains('username or password'));
  }, skip: skip);

  test('test() explains a wrong port', () async {
    final s = settingsFor('Fred').copyWith(port: 1);
    final r = await MqttService.test(s, clientId: 'flock-t3');
    expect(r.success, isFalse);
    expect(
      r.message.toLowerCase(),
      anyOf(contains('port'), contains('answer')),
    );
  }, skip: skip);

  test('Fred sees Mary, and can ask Mary for a fresh location', () async {
    final fred = MqttService();
    final mary = MqttService();
    addTearDown(() async {
      await fred.disconnect();
      await mary.disconnect();
    });

    final fredSettings = settingsFor('Fred');
    final marySettings = settingsFor('Mary');

    await mary.connect(marySettings, clientId: 'flock-mary');
    expect(mary.isConnected, isTrue, reason: mary.lastError.value);

    // Mary publishes a retained location and card before Fred is online.
    mary.publish(
      marySettings.ownTopic,
      OwnTracksProtocol.encodeLocation(
        lat: -33.87,
        lon: 151.21,
        timestamp: DateTime.now(),
        trackerId: 'MA',
        battery: 64,
      ),
    );
    mary.publish(
      '${marySettings.ownTopic}/info',
      OwnTracksProtocol.encodeCard(name: 'Mary Durk', trackerId: 'MA'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final gotLocation = Completer<IncomingMessage>();
    final gotCard = Completer<IncomingMessage>();
    final sub = fred.messages.listen((m) {
      if (m.topic == marySettings.ownTopic && !gotLocation.isCompleted) {
        gotLocation.complete(m);
      }
      if (m.topic == '${marySettings.ownTopic}/info' && !gotCard.isCompleted) {
        gotCard.complete(m);
      }
    });
    addTearDown(sub.cancel);

    await fred.connect(fredSettings, clientId: 'flock-fred');
    expect(fred.isConnected, isTrue, reason: fred.lastError.value);

    final loc = await gotLocation.future.timeout(const Duration(seconds: 5));
    final fix = OwnTracksProtocol.parseLocation(
      OwnTracksProtocol.decode(loc.payload)!,
    )!;
    expect(fix.battery, 64);
    expect(fix.lat, closeTo(-33.87, 1e-6));

    final card = await gotCard.future.timeout(const Duration(seconds: 5));
    expect(
      OwnTracksProtocol.parseCard(OwnTracksProtocol.decode(card.payload)!)!
          .name,
      'Mary Durk',
    );

    // Fred taps "Refresh" on Mary.
    final gotCmd = Completer<IncomingMessage>();
    final cmdSub = mary.messages.listen((m) {
      if (m.topic == '${marySettings.ownTopic}/cmd' && !gotCmd.isCompleted) {
        gotCmd.complete(m);
      }
    });
    addTearDown(cmdSub.cancel);
    fred.publish(
      '${marySettings.ownTopic}/cmd',
      OwnTracksProtocol.encodeReportLocationCommand(),
      retain: false,
    );
    final cmd = await gotCmd.future.timeout(const Duration(seconds: 5));
    expect(
      OwnTracksProtocol.isReportLocationCommand(
        OwnTracksProtocol.decode(cmd.payload)!,
      ),
      isTrue,
    );

    // Clean up retained messages so reruns start fresh.
    mary.publish(marySettings.ownTopic, '');
    mary.publish('${marySettings.ownTopic}/info', '');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }, skip: skip);

  test(
    'keeps retrying until the server comes back',
    () async {
      final dir = await Directory.systemTemp.createTemp('flock-mqtt');
      final conf = File('${dir.path}/m.conf')
        ..writeAsStringSync(
          'listener 18831 127.0.0.1\nallow_anonymous true\nuser root\n',
        );
      final svc = MqttService();
      Process? broker;
      addTearDown(() async {
        await svc.disconnect();
        broker?.kill();
        await dir.delete(recursive: true);
      });

      // No broker yet: first attempt fails but should schedule a retry.
      final s = settingsFor('Fred').copyWith(port: 18831, password: '');
      await svc.connect(s, clientId: 'flock-retry');
      expect(svc.status.value, ConnectionStatus.error);

      broker = await Process.start('mosquitto', ['-c', conf.path]);
      final connected = Completer<void>();
      void listener() {
        if (svc.status.value == ConnectionStatus.connected &&
            !connected.isCompleted) {
          connected.complete();
        }
      }

      svc.status.addListener(listener);
      await connected.future.timeout(const Duration(seconds: 15));
      svc.status.removeListener(listener);
      expect(svc.isConnected, isTrue);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
