import 'package:latlong2/latlong.dart';

import '../models/person.dart';
import 'format.dart';

/// A Life360-style day timeline built from raw location fixes:
/// places someone stayed, and the trips between them.
sealed class TimelineEntry {
  const TimelineEntry(this.start, this.end);
  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);
}

class Stay extends TimelineEntry {
  const Stay(super.start, super.end, this.center);
  final LatLng center;
}

class Trip extends TimelineEntry {
  const Trip(super.start, super.end, this.distanceMeters, this.path);
  final double distanceMeters;
  final List<LatLng> path;
}

/// Groups [fixes] (oldest first) into stays and trips.
///
/// A stay is any run of fixes within [stayRadius] of where it began that
/// lasts at least [minStay]. Everything between stays is a trip. Trips
/// shorter than [minTripMeters] are folded away as GPS jitter.
List<TimelineEntry> buildTimeline(
  List<LocationFix> fixes, {
  double stayRadius = 150,
  Duration minStay = const Duration(minutes: 5),
  double minTripMeters = 250,
}) {
  if (fixes.isEmpty) return const [];

  // 1. Find stay clusters.
  final clusters = <_Cluster>[];
  var i = 0;
  while (i < fixes.length) {
    final anchor = fixes[i].latLng;
    var j = i;
    var sumLat = 0.0, sumLon = 0.0;
    while (j < fixes.length &&
        metersBetween(anchor, fixes[j].latLng) <= stayRadius) {
      sumLat += fixes[j].lat;
      sumLon += fixes[j].lon;
      j++;
    }
    final start = fixes[i].timestamp;
    final end = fixes[j - 1].timestamp;
    if (end.difference(start) >= minStay) {
      final n = j - i;
      clusters.add(_Cluster(i, j - 1, LatLng(sumLat / n, sumLon / n)));
      i = j;
    } else {
      i++;
    }
  }

  // 2. Merge back-to-back stays at the same place (e.g. a GPS blip outside).
  final merged = <_Cluster>[];
  for (final c in clusters) {
    if (merged.isNotEmpty) {
      final prev = merged.last;
      final gap = fixes.sublist(prev.last, c.first + 1);
      if (metersBetween(prev.center, c.center) <= stayRadius &&
          _pathLength(gap) < minTripMeters) {
        merged[merged.length - 1] = _Cluster(prev.first, c.last, prev.center);
        continue;
      }
    }
    merged.add(c);
  }

  // 3. Emit stays and the trips between them.
  final out = <TimelineEntry>[];
  void addTrip(int from, int to) {
    if (to <= from) return;
    final seg = fixes.sublist(from, to + 1);
    final len = _pathLength(seg);
    if (len < minTripMeters) return;
    out.add(
      Trip(
        seg.first.timestamp,
        seg.last.timestamp,
        len,
        seg.map((f) => f.latLng).toList(),
      ),
    );
  }

  var cursor = 0;
  for (final c in merged) {
    addTrip(cursor, c.first);
    out.add(Stay(fixes[c.first].timestamp, fixes[c.last].timestamp, c.center));
    cursor = c.last;
  }
  addTrip(cursor, fixes.length - 1);
  return out;
}

double _pathLength(List<LocationFix> seg) {
  var total = 0.0;
  for (var k = 1; k < seg.length; k++) {
    total += metersBetween(seg[k - 1].latLng, seg[k].latLng);
  }
  return total;
}

class _Cluster {
  const _Cluster(this.first, this.last, this.center);
  final int first;
  final int last;
  final LatLng center;
}
