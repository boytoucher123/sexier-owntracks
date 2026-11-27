import 'package:latlong2/latlong.dart';

import '../models/person.dart';
import 'format.dart';
import 'timeline.dart';

/// One point of a day's track: a single report, or a stay (lots of reports
/// from one spot) that lasts from [start] to [end].
class TrackPoint {
  const TrackPoint(this.pos, this.start, this.end, {this.fix, this.stay});
  final LatLng pos;
  final DateTime start;
  final DateTime end;

  /// The report itself (battery, speed), or the stay's last report.
  final LocationFix? fix;
  final Stay? stay;
  bool get isStay => stay != null;
}

enum TrackState {
  /// Before the first report of the day.
  before,

  /// At a stay.
  staying,

  /// Between two reports while moving: the position is estimated.
  moving,

  /// Between two reports with data missing (lost signal, phone off).
  gap,

  /// After the last report.
  after,
}

/// Where someone was at a moment of the day.
class TrackMoment {
  const TrackMoment(this.pos, this.state, {this.point, this.from, this.to});
  final LatLng pos;
  final TrackState state;

  /// The point we're at or just passed.
  final TrackPoint? point;

  /// For [TrackState.gap]: the missing stretch.
  final DateTime? from;
  final DateTime? to;
}

/// A day's reports as something you can move through by time.
class DayTrack {
  DayTrack._(this.points, this.gaps);

  /// [fixes] oldest first.
  factory DayTrack(List<LocationFix> fixes) {
    final stays = buildTimeline(fixes).whereType<Stay>().toList();
    final points = <TrackPoint>[];
    var k = 0;
    var i = 0;
    while (i < fixes.length) {
      final f = fixes[i];
      while (k < stays.length && stays[k].end.isBefore(f.timestamp)) {
        k++;
      }
      final stay = k < stays.length ? stays[k] : null;
      if (stay == null || f.timestamp.isBefore(stay.start)) {
        points.add(TrackPoint(f.latLng, f.timestamp, f.timestamp, fix: f));
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < fixes.length &&
          !fixes[j + 1].timestamp.isAfter(stay.end)) {
        j++;
      }
      points.add(
        TrackPoint(
          stay.center,
          stay.start,
          stay.end,
          fix: fixes[j],
          stay: stay,
        ),
      );
      i = j + 1;
      k++;
    }
    final gaps = <int>{
      for (var p = 0; p + 1 < points.length; p++)
        if (isMissingData(points[p], points[p + 1])) p,
    };
    return DayTrack._(points, gaps);
  }

  final List<TrackPoint> points;

  /// Indexes `p` where the stretch from points[p] to points[p+1] has data
  /// missing.
  final Set<int> gaps;

  bool get isEmpty => points.isEmpty;

  /// Reports stopped for a while and they turned up somewhere else: the
  /// phone wasn't reporting (no signal, off, app stopped), so the line
  /// between is a guess. Phones report every ~100-500 m when moving, so a
  /// long silence followed by a jump means data was lost.
  static bool isMissingData(TrackPoint a, TrackPoint b) {
    final dt = b.start.difference(a.end);
    final d = metersBetween(a.pos, b.pos);
    return (dt >= const Duration(minutes: 15) && d >= 1000) ||
        (dt >= const Duration(hours: 1) && d >= 300);
  }

  /// Index of the last point starting at or before [t], or -1.
  int indexAt(DateTime t) {
    var lo = 0, hi = points.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!points[mid].start.isAfter(t)) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Where they were at [t].
  TrackMoment? at(DateTime t) {
    if (points.isEmpty) return null;
    final k = indexAt(t);
    if (k < 0) {
      return TrackMoment(
        points.first.pos,
        TrackState.before,
        point: points.first,
      );
    }
    final p = points[k];
    if (!t.isAfter(p.end)) {
      return TrackMoment(
        p.pos,
        p.isStay ? TrackState.staying : TrackState.moving,
        point: p,
      );
    }
    if (k == points.length - 1) {
      return TrackMoment(p.pos, TrackState.after, point: p);
    }
    final q = points[k + 1];
    final span = q.start.difference(p.end).inMilliseconds;
    final f = span <= 0 ? 1.0 : t.difference(p.end).inMilliseconds / span;
    final pos = LatLng(
      p.pos.latitude + (q.pos.latitude - p.pos.latitude) * f,
      p.pos.longitude + (q.pos.longitude - p.pos.longitude) * f,
    );
    if (gaps.contains(k)) {
      return TrackMoment(
        pos,
        TrackState.gap,
        point: p,
        from: p.end,
        to: q.start,
      );
    }
    return TrackMoment(pos, TrackState.moving, point: p);
  }
}
