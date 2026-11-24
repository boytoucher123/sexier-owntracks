import 'package:flock/models/person.dart';
import 'package:flock/util/format.dart';
import 'package:flock/util/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

LocationFix fix(double lat, double lon, int minute) => LocationFix(
  lat: lat,
  lon: lon,
  timestamp: DateTime(2026, 11, 24, 8).add(Duration(minutes: minute)),
);

void main() {
  test('empty history gives empty timeline', () {
    expect(buildTimeline(const []), isEmpty);
  });

  test('home, drive, school becomes stay / trip / stay', () {
    // ~0.01 deg lat ≈ 1.1 km
    final fixes = [
      for (var m = 0; m <= 30; m += 5) fix(-33.80, 151.00, m), // home 30 min
      fix(-33.81, 151.00, 35),
      fix(-33.82, 151.00, 40),
      fix(-33.83, 151.00, 45),
      for (var m = 50; m <= 90; m += 5) fix(-33.84, 151.00, m), // school
    ];
    final tl = buildTimeline(fixes);
    expect(tl.map((e) => e.runtimeType).toList(), [Stay, Trip, Stay]);
    final trip = tl[1] as Trip;
    expect(trip.distanceMeters, greaterThan(3000));
    expect(tl.first.duration, const Duration(minutes: 30));
  });

  test('GPS jitter at one place is a single stay', () {
    final fixes = [
      for (var m = 0; m < 60; m += 3)
        fix(-33.80 + (m.isEven ? 0.0003 : -0.0003), 151.00, m),
    ];
    final tl = buildTimeline(fixes);
    expect(tl.length, 1);
    expect(tl.single, isA<Stay>());
  });

  test('formatting helpers', () {
    final now = DateTime(2026, 11, 24, 12);
    expect(
      timeAgo(now.subtract(const Duration(seconds: 20)), now: now),
      'Just now',
    );
    expect(
      timeAgo(now.subtract(const Duration(minutes: 4)), now: now),
      '4 min ago',
    );
    expect(timeAgo(DateTime(2026, 11, 23, 18, 4), now: now), 'Yesterday 18:04');
    expect(formatDistance(850), '850 m');
    expect(formatDistance(2340), '2.3 km');
    expect(formatDuration(const Duration(minutes: 75)), '1 h 15 min');
    expect(dayLabel(now, now: now), 'Today');
  });
}
