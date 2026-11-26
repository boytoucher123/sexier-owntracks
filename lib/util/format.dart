import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../strings.dart';

/// "Just now", "4 min ago", "2 h ago", "Yesterday 18:04", "Mon 09:12".
String timeAgo(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 60) return Txt.justNow;
  if (d.inMinutes < 60) return Txt.minAgo(d.inMinutes);
  if (d.inHours < 12) return Txt.hAgo(d.inHours);
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = DateFormat.Hm().format(t);
  if (day == today) return Txt.today(hm);
  if (day == today.subtract(const Duration(days: 1))) return Txt.yesterday(hm);
  if (today.difference(day).inDays < 7) {
    return '${DateFormat.E().format(t)} $hm';
  }
  return DateFormat.MMMd().add_Hm().format(t);
}

/// True when a fix is old enough that people should be warned it's stale.
bool isStale(DateTime t, {DateTime? now}) =>
    (now ?? DateTime.now()).difference(t) > const Duration(hours: 1);

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) return Txt.km((meters / 1000).toStringAsFixed(1));
  return Txt.km((meters / 1000).round());
}

String formatDuration(Duration d) {
  if (d.inMinutes < 1) return Txt.n1Min;
  if (d.inMinutes < 60) return Txt.min(d.inMinutes);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '$h h' : Txt.hMin(h, m);
}

const _distance = Distance();

double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

String dayLabel(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return Txt.today2;
  if (d == today.subtract(const Duration(days: 1))) return Txt.yesterday2;
  return DateFormat('EEE d').format(d);
}
