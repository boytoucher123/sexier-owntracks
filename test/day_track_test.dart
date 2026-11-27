import 'package:flock/models/person.dart';
import 'package:flock/util/day_track.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 11, 25);
DateTime _at(int h, [int m = 0]) => _day.add(Duration(hours: h, minutes: m));
LocationFix _fix(double lat, double lon, DateTime t) =>
    LocationFix(lat: lat, lon: lon, timestamp: t);

/// Home 7-8, drive, work 8:30 to 5 pm, then the phone goes quiet and turns up
/// 10 km away at 10 pm.
List<LocationFix> _dayOfFixes() => [
  for (var m = 0; m <= 60; m += 5) _fix(-33.8968, 151.1793, _at(7, m)),
  _fix(-33.8900, 151.1900, _at(8, 10)),
  _fix(-33.8800, 151.2000, _at(8, 20)),
  for (var m = 30; m <= 17 * 60 - 8 * 60; m += 20)
    _fix(-33.8679, 151.2073, _at(8, m)),
  _fix(-33.8679, 151.2073, _at(17)),
  for (var m = 0; m <= 30; m += 10) _fix(-33.7800, 151.2800, _at(22, m)),
];

void main() {
  test('a stay holds its spot for its whole length', () {
    final track = DayTrack(_dayOfFixes());
    final work = track.at(_at(11, 53))!;
    expect(work.state, TrackState.staying);
    expect(work.pos.latitude, closeTo(-33.8679, 0.0002));
    expect(work.point!.start, _at(8, 30));
    expect(work.point!.end, _at(17));
    // Still there at 4:59, not after 5.
    expect(track.at(_at(16, 59))!.state, TrackState.staying);
    expect(track.at(_at(17, 1))!.state, isNot(TrackState.staying));
  });

  test('between reports the position is estimated by time', () {
    final track = DayTrack(_dayOfFixes());
    final m = track.at(_at(8, 15))!; // halfway between 8:10 and 8:20
    expect(m.state, TrackState.moving);
    expect(m.pos.latitude, closeTo(-33.8850, 0.0002));
  });

  test('a long silence then a jump is missing data', () {
    final track = DayTrack(_dayOfFixes());
    expect(track.gaps, hasLength(1));
    final m = track.at(_at(19))!;
    expect(m.state, TrackState.gap);
    expect((m.from, m.to), (_at(17), _at(22)));
    // A long stay is not a gap.
    expect(DayTrack.isMissingData(track.points[0], track.points[1]), isFalse);
  });

  test('before the first and after the last report', () {
    final track = DayTrack(_dayOfFixes());
    expect(track.at(_at(3))!.state, TrackState.before);
    expect(track.at(_at(3))!.point!.start, _at(7));
    expect(track.at(_at(23, 50))!.state, TrackState.after);
    expect(DayTrack(const []).at(_at(12)), isNull);
  });
}
