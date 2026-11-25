// Renders the real app screens with demo data and saves PNGs to
// docs/screenshots/. Skipped unless SCREENSHOTS=1:
//
//   SCREENSHOTS=1 flutter test test/screenshots/screenshots_test.dart
//
// Map tiles are drawn locally (a stylised placeholder), because tests can't
// load network tiles. Everything else is the real UI.
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flock/main.dart';
import 'package:flock/models/person.dart';
import 'package:flock/models/settings.dart';
import 'package:flock/screens/photo_crop_screen.dart';
import 'package:flock/services/location_service.dart';
import 'package:flock/services/mqtt_service.dart';
import 'package:flock/services/owntracks_protocol.dart';
import 'package:flock/services/platform_services.dart';
import 'package:flock/services/recorder_service.dart';
import 'package:flock/services/settings_store.dart';
import 'package:flock/state/app_state.dart';
import 'package:flock/widgets/family_map.dart';
import 'package:flock/widgets/history_joystick.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _out = 'docs/screenshots';
const _size = Size(390, 844);
const _dpr = 2.0;

// ------------------------------------------------------------------ fakes --

class _Store extends SettingsStore {
  _Store(this.s);
  AppSettings s;
  @override
  Future<AppSettings> load() async => s;
  @override
  Future<void> save(AppSettings v) async => s = v;
  @override
  Future<Uint8List?> loadFace() async => null;
  @override
  Future<void> saveFace(Uint8List? b) async {}
  @override
  Future<String> clientIdSuffix() async => 'k3x9q2ab';
}

class _Mqtt extends MqttService {
  final _ctl = StreamController<IncomingMessage>.broadcast();
  @override
  Stream<IncomingMessage> get messages => _ctl.stream;
  void inject(String topic, String payload) =>
      _ctl.add(IncomingMessage(topic, payload));
  @override
  Future<void> connect(AppSettings s, {required String clientId}) async {
    status.value = ConnectionStatus.connected;
    onConnected?.call();
  }

  @override
  bool publish(String topic, String payload, {bool retain = true}) => true;
  @override
  Future<void> disconnect() async {}
}

class _Location extends LocationService {
  _Location(this.a);
  LocationAccess a;
  @override
  Future<LocationAccess> access() async => a;
  @override
  Future<void> start(TrackingMode mode) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> reportNow(String trigger) async {}
}

class _Recorder extends RecorderService {
  _Recorder(this.fixes);
  final List<LocationFix> fixes;
  @override
  Future<List<LocationFix>> history(
    AppSettings s, {
    required String user,
    required String device,
    required DateTime from,
    DateTime? to,
  }) async => fixes;
}

class _State extends AppState {
  _State({super.store, super.mqtt, super.location, super.recorder});
  @override
  Future<ConnectionTestResult> testConnection(AppSettings c) async =>
      const ConnectionTestResult.ok();
}

/// Draws a believable street map in global pixel space so tiles line up.
class _Tiles extends fm.TileProvider {
  final _cache = <String, Uint8List>{};
  @override
  ImageProvider getImage(fm.TileCoordinates c, fm.TileLayer o) =>
      MemoryImage(_cache.putIfAbsent('${c.z}/${c.x}/${c.y}', () => _draw(c)));

  static int _hash(int a, int b) {
    var h = a * 374761393 + b * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0x7fffffff;
  }

  Uint8List _draw(fm.TileCoordinates c) {
    const n = 256;
    final im = img.Image(width: n, height: n);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final gx = c.x * n + i, gy = c.y * n + j;
        // base
        var r = 245, g = 243, b = 238;
        // parks: some blocks green
        final bx = gx ~/ 384, by = gy ~/ 384;
        if (_hash(bx, by) % 23 == 0) {
          r = 206;
          g = 234;
          b = 196;
        }
        // river
        final d = (gy - (gx * 0.42) - 380 + 60 * _wave(gx)).abs();
        if (d < 46) {
          r = 170;
          g = 211;
          b = 240;
        }
        // streets
        final mx = gx % 96, my = gy % 96;
        final major = (gx % 576 < 9) || (gy % 576 < 9);
        if (major && d >= 46) {
          r = 255;
          g = 255;
          b = 255;
          if (gx % 576 < 2 ||
              gx % 576 > 6 && gx % 576 < 9 ||
              gy % 576 < 2 ||
              gy % 576 > 6 && gy % 576 < 9) {
            r = 228;
            g = 222;
            b = 212;
          }
        } else if ((mx < 3 || my < 3) && d >= 46) {
          r = 255;
          g = 255;
          b = 255;
        }
        // diagonal arterial
        final diag = ((gx + gy) % 1400 - 700).abs();
        if (diag < 6 && d >= 46) {
          r = 255;
          g = 226;
          b = 160;
        }
        im.setPixelRgb(i, j, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  static double _wave(int x) {
    final t = (x % 2000) / 2000.0;
    return (t < 0.5 ? t : 1 - t) * 2 - 0.5;
  }
}

// --------------------------------------------------------------- demo data --

DateTime _ago(int minutes) =>
    DateTime.now().subtract(Duration(minutes: minutes));

String _loc(
  double lat,
  double lon,
  int minsAgo,
  String tid, {
  int batt = 80,
  bool charging = false,
  double speed = 0,
}) => OwnTracksProtocol.encodeLocation(
  lat: lat,
  lon: lon,
  timestamp: _ago(minsAgo),
  trackerId: tid,
  battery: batt,
  charging: charging,
  speedMetersPerSecond: speed,
  accuracy: 10,
);

const _fred = (-33.8968, 151.1793);
const _mary = (-33.8679, 151.2073);
const _jack = (-33.8790, 151.1855);
const _sophie = (-33.9105, 151.1560);

void _seedAddresses() {
  AddressLookup.seed(_fred.$1, _fred.$2, '12 Wilson St, Newtown');
  AddressLookup.seed(_mary.$1, _mary.$2, '1 Martin Pl, Sydney');
  AddressLookup.seed(_jack.$1, _jack.$2, 'Glebe Public School, Glebe');
  AddressLookup.seed(_sophie.$1, _sophie.$2, '48 Illawarra Rd, Marrickville');
  AddressLookup.seed(-33.8968, 151.1793, '12 Wilson St, Newtown');
  AddressLookup.seed(-33.8850, 151.1950, 'Paramount Coffee, Surry Hills');
}

List<LocationFix> _maryDay() {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day, 7, 0);
  final out = <LocationFix>[];
  void stay(double lat, double lon, int fromMin, int toMin) {
    for (var m = fromMin; m <= toMin; m += 5) {
      out.add(
        LocationFix(
          lat: lat,
          lon: lon,
          timestamp: start.add(Duration(minutes: m)),
        ),
      );
    }
  }

  void drive(List<(double, double)> pts, int fromMin, int toMin) {
    for (var k = 0; k < pts.length; k++) {
      final m =
          fromMin + ((toMin - fromMin) * (k + 1) / (pts.length + 1)).round();
      out.add(
        LocationFix(
          lat: pts[k].$1,
          lon: pts[k].$2,
          timestamp: start.add(Duration(minutes: m)),
        ),
      );
    }
  }

  stay(-33.8968, 151.1793, 0, 65); // home
  drive(
    [(-33.8930, 151.1830), (-33.8890, 151.1890), (-33.8860, 151.1930)],
    65,
    90,
  );
  stay(-33.8850, 151.1950, 90, 115); // coffee
  drive(
    [(-33.8800, 151.2000), (-33.8740, 151.2040), (-33.8700, 151.2060)],
    115,
    140,
  );
  stay(_mary.$1, _mary.$2, 140, 300); // work
  return out;
}

// ---------------------------------------------------------------- harness --

Future<void> _loadFonts() async {
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String f) async =>
      ByteData.view((await File('$dir/$f').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final w in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    if (File('$dir/Roboto-$w.ttf').existsSync()) {
      roboto.addFont(bytes('Roboto-$w.ttf'));
    }
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _settle(WidgetTester t, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _shot(WidgetTester t, String name) async {
  await _settle(t);
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  final bytes = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

Future<(_State, _Mqtt)> _boot(
  WidgetTester t, {
  required AppSettings settings,
  LocationAccess access = LocationAccess.always,
  ThemeMode mode = ThemeMode.light,
}) async {
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
  t.view.physicalSize = _size * _dpr;
  t.view.devicePixelRatio = _dpr;
  addTearDown(t.view.reset);
  final mqtt = _Mqtt();
  final state = _State(
    store: _Store(settings),
    mqtt: mqtt,
    location: _Location(access),
    recorder: _Recorder(_maryDay()),
  );
  await t.runAsync(state.init);
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: FlockApp(state: state, themeMode: mode),
    ),
  );
  await t.pump();
  return (state, mqtt);
}

const _crew = AppSettings(
  host: 'tracking.thecrew.net',
  username: 'crew',
  password: 'x',
  deviceName: 'Fred',
  displayName: 'Fred Durk',
  trackerId: 'FD',
  recorderUrl: 'https://tracking.thecrew.net/owntracks',
  setupComplete: true,
);

void _populate(_Mqtt m) {
  const b = 'owntracks/crew';
  m.inject('$b/Fred', _loc(_fred.$1, _fred.$2, 1, 'FD', batt: 72));
  m.inject('$b/Maya', _loc(_mary.$1, _mary.$2, 4, 'MC', batt: 54));
  m.inject(
    '$b/Maya/info',
    OwnTracksProtocol.encodeCard(name: 'Maya Chen', trackerId: 'MC'),
  );
  m.inject('$b/Jack', _loc(_jack.$1, _jack.$2, 12, 'JL', batt: 23));
  m.inject(
    '$b/Jack/info',
    OwnTracksProtocol.encodeCard(name: 'Jack Lee', trackerId: 'JL'),
  );
  m.inject(
    '$b/Sophie',
    _loc(_sophie.$1, _sophie.$2, 2, 'SN', batt: 91, charging: true, speed: 11),
  );
  m.inject(
    '$b/Sophie/info',
    OwnTracksProtocol.encodeCard(name: 'Sophie Nguyen', trackerId: 'SN'),
  );
}

void main() {
  final skip = Platform.environment['SCREENSHOTS'] == '1'
      ? null
      : 'set SCREENSHOTS=1';

  setUpAll(() async {
    if (skip != null) return;
    await _loadFonts();
    FamilyMap.debugTileProvider = _Tiles();
    _seedAddresses();
  });

  testWidgets('onboarding', (t) async {
    await _boot(
      t,
      settings: const AppSettings(),
      access: LocationAccess.notAsked,
    );
    await _shot(t, '01-welcome');

    await t.tap(find.text('Get started'));
    await _settle(t);
    await t.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'tracking.thecrew.net',
    );
    await t.enterText(find.widgetWithText(TextField, 'Username'), 'crew');
    await t.enterText(
      find.widgetWithText(TextField, 'Password'),
      'hunter2hunter2',
    );
    await t.tap(find.text('Test connection'));
    await _shot(t, '02-connect');

    await t.tap(find.text('Continue'));
    await _settle(t);
    await t.enterText(find.widgetWithText(TextField, 'Your name'), 'Fred Durk');
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(t, '03-you');

    await t.tap(find.text('Continue'));
    await _settle(t);
    // History is pre-filled for this server, so the button says Continue.
    await t.tap(find.text('Continue'));
    await _shot(t, '04-location');
  }, skip: skip != null);

  testWidgets('home', (t) async {
    final (state, mqtt) = await _boot(t, settings: _crew);
    _populate(mqtt);
    await _shot(t, '05-home');

    await t.tap(find.text('Maya Chen'));
    await _shot(t, '06-person');

    await t.tap(find.text('History'));
    await _settle(t);
    await _shot(t, '07-history');

    // Tap a point on the way to coffee: its time and address show.
    await t.tap(find.byType(TrailDot).at(2), warnIfMissed: false);
    await _shot(t, '12-history-point');

    // Hold the joystick to the left: travelling back through the day.
    final g = await t.startGesture(t.getCenter(find.byType(HistoryJoystick)));
    await g.moveBy(const Offset(-30, 0));
    await g.moveBy(const Offset(-50, 0));
    await t.pump(const Duration(milliseconds: 200));
    await _shot(t, '13-history-joystick');
    await g.up();
    expect(state.people.length, 4);
  }, skip: skip != null);

  testWidgets('sheet lowered', (t) async {
    final (_, mqtt) = await _boot(t, settings: _crew);
    _populate(mqtt);
    await _settle(t);
    await t.timedDrag(
      find.text('People'),
      const Offset(0, 600),
      const Duration(milliseconds: 600),
    );
    await _shot(t, '10-sheet-lowered');
  }, skip: skip != null);

  testWidgets('photo crop', (t) async {
    await _boot(t, settings: _crew);
    final photo = img.Image(width: 900, height: 600);
    for (final px in photo) {
      px
        ..r = 60 + px.x * 180 ~/ 900
        ..g = 90 + px.y * 120 ~/ 600
        ..b = 200 - px.x * 120 ~/ 900;
    }
    img.fillCircle(
      photo,
      x: 450,
      y: 260,
      radius: 150,
      color: img.ColorRgb8(250, 210, 170),
    );
    final bytes = Uint8List.fromList(img.encodePng(photo));
    final nav = Navigator.of(t.element(find.byType(Scaffold).first));
    unawaited(PhotoCropScreen.open(nav.context, bytes));
    await _settle(t, rounds: 10);
    await _shot(t, '11-photo-crop');
  }, skip: skip != null);

  testWidgets('home dark', (t) async {
    final (_, mqtt) = await _boot(t, settings: _crew, mode: ThemeMode.dark);
    _populate(mqtt);
    await _shot(t, '08-home-dark');
  }, skip: skip != null);

  testWidgets('settings', (t) async {
    final (_, mqtt) = await _boot(t, settings: _crew);
    _populate(mqtt);
    await _settle(t);
    await t.tap(find.byTooltip('Settings'));
    await _shot(t, '09-settings');
  }, skip: skip != null);
}
