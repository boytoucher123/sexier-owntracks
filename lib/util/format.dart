import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

/// "Just now", "4 min ago", "2 h ago", "Yesterday 18:04", "Mon 09:12".
String timeAgo(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 12) return '${d.inHours} h ago';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = DateFormat.Hm().format(t);
  if (day == today) return 'Today $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $hm';
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
  if (meters < 10000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1000).round()} km';
}

String formatDuration(Duration d) {
  if (d.inMinutes < 1) return '<1 min';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

const _distance = Distance();

double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

String dayLabel(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEE d').format(d);
}
