// ignore_for_file: deprecated_member_use
import 'package:flock/models/person.dart';
import 'package:flock/screens/history_screen.dart';
import 'package:flock/util/timeline.dart';
import 'package:flock/widgets/history_joystick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LocationFix _fix(double lat, double lon, int minute) => LocationFix(
  lat: lat,
  lon: lon,
  timestamp: DateTime(2026, 11, 25, 9, minute),
);

void main() {
  group('stays', () {
    test('lots of reports from one spot play back as one stop', () {
      final fixes = [
        _fix(-33.8000, 151.2000, 0), // on the way
        _fix(-33.8100, 151.2000, 2),
        for (var m = 5; m <= 40; m += 1)
          _fix(-33.82 + (m % 3) * 0.00002, 151.2, m), // at the beach
        _fix(-33.8300, 151.2000, 45), // leaving
        _fix(-33.8400, 151.2000, 48),
      ];
      final stays = buildTimeline(fixes).whereType<Stay>().toList();
      expect(stays, hasLength(1));
      final played = collapseStays(fixes, stays);
      // 2 before + 1 stay + 2 after, instead of 40 points.
      expect(played.fixes, hasLength(5));
      expect(played.until.where((u) => u != null), hasLength(1));
      final i = played.until.indexWhere((u) => u != null);
      expect(played.fixes[i].timestamp, DateTime(2026, 11, 25, 9, 5));
      expect(played.until[i], DateTime(2026, 11, 25, 9, 40));
      expect(played.fixes[i].lat, closeTo(-33.82, 0.0001));
    });

    test('no stays: nothing changes', () {
      final fixes = [_fix(-33.80, 151.2, 0), _fix(-33.81, 151.2, 1)];
      final played = collapseStays(fixes, const []);
      expect(played.fixes, fixes);
      expect(played.until, [null, null]);
    });
  });

  group('history playback', () {
    test(
      'joystick speed: still in the middle, gentle near it, fast at the edge',
      () {
        expect(historySpeed(0), 0);
        expect(historySpeed(0.02), 0);
        expect(historySpeed(0.1), inInclusiveRange(0.5, 1.5));
        expect(historySpeed(-0.1), historySpeed(0.1));
        expect(historySpeed(1), greaterThan(40));
        expect(historySpeed(0.5), lessThan(historySpeed(0.8)));
      },
    );

    test('dots skip points where someone sat still, keep both ends', () {
      final fixes = [
        _fix(-33.8700, 151.2000, 0),
        _fix(-33.87001, 151.20001, 1), // ~1 m: skipped
        _fix(-33.87002, 151.20002, 2), // still there: skipped
        _fix(-33.8710, 151.2000, 3), // ~110 m: dot
        _fix(-33.87101, 151.2000, 4), // last: always a dot
      ];
      expect(historyDotIndices(fixes), [0, 3, 4]);
      expect(historyDotIndices(const []), isEmpty);
    });

    test('position glides between points', () {
      final fixes = [_fix(0, 0, 0), _fix(1, 2, 1)];
      final mid = historyPositionAt(fixes, 0.5);
      expect(mid.latitude, closeTo(0.5, 1e-9));
      expect(mid.longitude, closeTo(1, 1e-9));
      expect(historyPositionAt(fixes, 1).latitude, 1);
      expect(historyPositionAt(fixes, 5).latitude, 1);
    });
  });

  group('joystick', () {
    Future<(List<double>, List<int>)> pump(WidgetTester t) async {
      final pushes = <double>[];
      final steps = <int>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: HistoryJoystick(
                  color: Colors.purple,
                  onChanged: pushes.add,
                  onStep: steps.add,
                ),
              ),
            ),
          ),
        ),
      );
      return (pushes, steps);
    }

    testWidgets('push left goes earlier, harder is faster, release stops', (
      t,
    ) async {
      final (pushes, _) = await pump(t);
      final g = await t.startGesture(t.getCenter(find.byType(HistoryJoystick)));
      await g.moveBy(const Offset(-30, 0)); // past the touch slop
      await t.pump();
      await g.moveBy(const Offset(-20, 0));
      await t.pump();
      final soft = pushes.last;
      expect(soft, lessThan(0));
      await g.moveBy(const Offset(-40, 0));
      await t.pump();
      expect(pushes.last, lessThan(soft)); // pushed further
      await g.moveBy(const Offset(-500, 0));
      await t.pump();
      expect(pushes.last, -1); // capped
      await g.up();
      await t.pumpAndSettle();
      expect(pushes.last, 0); // springs back
    });

    testWidgets('push right goes later', (t) async {
      final (pushes, _) = await pump(t);
      final g = await t.startGesture(t.getCenter(find.byType(HistoryJoystick)));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(40, 0));
      await t.pump();
      expect(pushes.last, greaterThan(0));
      await g.up();
      await t.pumpAndSettle();
      expect(pushes.last, 0);
    });

    testWidgets('tapping a side steps one point', (t) async {
      final (_, steps) = await pump(t);
      final box = t.getRect(find.byType(HistoryJoystick));
      await t.tapAt(Offset(box.left + 20, box.center.dy));
      await t.tapAt(Offset(box.right - 20, box.center.dy));
      expect(steps, [-1, 1]);
    });
  });
}
