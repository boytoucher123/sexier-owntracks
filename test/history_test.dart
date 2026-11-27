// ignore_for_file: deprecated_member_use
import 'package:flock/screens/history_screen.dart';
import 'package:flock/widgets/history_joystick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
