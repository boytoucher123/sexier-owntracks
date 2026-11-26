// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/server_config.dart';
import '../models/person.dart';
import '../services/platform_services.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/timeline.dart';
import '../widgets/avatar.dart';
import '../widgets/family_map.dart';
import '../widgets/history_joystick.dart';
import '../strings.dart';

/// Points per second for a joystick push of 0..1. Gentle near the centre
/// (about one point a second, for following a street) and fast at the edge
/// (a whole day in a few seconds).
@visibleForTesting
double historySpeed(double push) {
  final a = push.abs().clamp(0.0, 1.0);
  if (a < 0.04) return 0;
  return 0.8 + 45 * a * a * a;
}

/// Which fixes get a dot on the map. Fixes closer than [minMeters] to the
/// previous dot (someone sitting still) are skipped so dots don't pile up.
/// The first and last fix always get one.
@visibleForTesting
List<int> historyDotIndices(List<LocationFix> fixes, {double minMeters = 25}) {
  if (fixes.isEmpty) return const [];
  final out = <int>[0];
  for (var i = 1; i < fixes.length; i++) {
    final isLast = i == fixes.length - 1;
    if (isLast ||
        metersBetween(fixes[out.last].latLng, fixes[i].latLng) >= minMeters) {
      out.add(i);
    }
  }
  return out;
}

/// The position at a fractional index, between two fixes.
@visibleForTesting
LatLng historyPositionAt(List<LocationFix> fixes, double pos) {
  final i = pos.floor().clamp(0, fixes.length - 1);
  if (i >= fixes.length - 1) return fixes.last.latLng;
  final f = pos - i;
  final a = fixes[i], b = fixes[i + 1];
  return LatLng(a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f);
}

/// "Daily history": one person's day on the map, with a joystick to travel
/// through it.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.person});
  final Person person;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final _map = FamilyMapController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  DateTime _lastFollow = DateTime.fromMillisecondsSinceEpoch(0);

  int _dayOffset = 0; // 0 = today, 1 = yesterday ...
  int _request = 0;
  bool _loading = true;
  String? _error;
  List<LocationFix> _fixes = const [];
  List<int> _dots = const [];
  List<LatLng> _stops = const [];

  double _pos = 0; // fractional index into _fixes
  double _stick = 0; // joystick push, -1..1

  static const _topInset = 84.0;
  static const _panelHeight = 228.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load(int day) async {
    final req = ++_request;
    _setStick(0);
    setState(() {
      _dayOffset = day;
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: day));
    final end = day == 0 ? now : start.add(const Duration(days: 1));
    try {
      final fixes = await context.read<AppState>().history(
        widget.person,
        start,
        end,
      );
      if (!mounted || req != _request) return;
      setState(() {
        _fixes = fixes;
        _dots = historyDotIndices(fixes);
        _stops = buildTimeline(fixes)
            .whereType<Stay>()
            .map((s) => s.center)
            .toList();
        // Start at the latest point: "where were they last?"
        _pos = fixes.isEmpty ? 0 : (fixes.length - 1).toDouble();
        _loading = false;
      });
      if (fixes.isNotEmpty) {
        _map.fit(fixes.map((f) => f.latLng).toList());
      }
    } on Object catch (e) {
      if (!mounted || req != _request) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _fixes = const [];
        _dots = const [];
        _stops = const [];
      });
    }
  }

  // ------------------------------------------------------------ movement --

  void _setStick(double v) {
    _stick = v;
    if (v != 0 && !_ticker.isActive && _fixes.length > 1) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (v == 0 && _ticker.isActive) {
      _ticker.stop();
      // Settle on the nearest real point so the time and address are exact.
      if (_fixes.isNotEmpty) setState(() => _pos = _pos.roundToDouble());
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final speed = historySpeed(_stick);
    if (speed == 0 || _fixes.length < 2) return;
    final last = (_fixes.length - 1).toDouble();
    final next = (_pos + _stick.sign * speed * dt).clamp(0.0, last);
    if (next == _pos) return;
    // A tick for each point passed, when moving slowly enough to feel it.
    if (speed < 6 && next.round() != _pos.round()) {
      HapticFeedback.selectionClick();
    }
    setState(() => _pos = next);
    _follow();
  }

  void _step(int dir) {
    if (_fixes.isEmpty) return;
    final target = (_pos.round() + dir).clamp(0, _fixes.length - 1);
    setState(() => _pos = target.toDouble());
    _follow(force: true);
  }

  void _jumpToDot(int dot) {
    _setStick(0);
    setState(() => _pos = _dots[dot].toDouble());
    HapticFeedback.selectionClick();
    _follow(force: true);
  }

  /// Keep the moving avatar on screen without fighting the person's own pans.
  void _follow({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastFollow).inMilliseconds < 250) return;
    _lastFollow = now;
    _map.ensureVisible(historyPositionAt(_fixes, _pos));
  }

  // -------------------------------------------------------------- build --

  LocationFix? get _current => _fixes.isEmpty ? null : _fixes[_pos.round()];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = widget.person;
    final color = FlockColors.forKey(p.topic);
    final media = MediaQuery.of(context);
    final cur = _current;

    // The person's pin rides along the trail.
    final pin = cur == null
        ? null
        : Person(
            topic: p.topic,
            user: p.user,
            device: p.device,
            cardName: p.cardName,
            face: p.face,
            trackerId: p.trackerId,
            last: LocationFix(
              lat: historyPositionAt(_fixes, _pos).latitude,
              lon: historyPositionAt(_fixes, _pos).longitude,
              timestamp: cur.timestamp,
            ),
          );
    final selectedDot = _stick == 0 ? _dots.indexOf(_pos.round()) : -1;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar.person(p, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, overflow: TextOverflow.ellipsis),
                  Text(
                    Txt.dailyHistory,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FamilyMap(
              provider: app.mapProvider,
              style: app.settings.mapStyle,
              controller: _map,
              people: [?pin],
              selectedTopic: p.topic,
              onPersonTap: (_) {},
              trail: _fixes.map((f) => f.latLng).toList(),
              trailStops: _stops,
              trailColor: color,
              nodes: [for (final i in _dots) _fixes[i].latLng],
              selectedNode: selectedDot < 0 ? null : selectedDot,
              onNodeTap: _jumpToDot,
              markStale: false,
              topInset: _topInset,
              bottomInset: _panelHeight + media.padding.bottom,
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _DayBar(
              dayOffset: _dayOffset,
              loading: _loading,
              onEarlier: _dayOffset < kHistoryDays - 1
                  ? () => _load(_dayOffset + 1)
                  : null,
              onLater: _dayOffset > 0 ? () => _load(_dayOffset - 1) : null,
            ),
          ),
          if (!_loading && (_error != null || _fixes.isEmpty))
            Positioned(
              top: _topInset + 16,
              left: 32,
              right: 32,
              child: _Notice(
                icon: _error != null
                    ? Icons.cloud_off_rounded
                    : Icons.nightlight_round,
                text: _error ?? Txt.noLocationsRecordedOnThis,
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 16,
            child: _Panel(
              fixes: _fixes,
              pos: _pos,
              moving: _stick != 0,
              color: color,
              onStick: (v) => _setStick(v),
              onStep: _step,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- widgets --

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.dayOffset,
    required this.loading,
    required this.onEarlier,
    required this.onLater,
  });

  final int dayOffset;
  final bool loading;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final day = now.subtract(Duration(days: dayOffset));
    final label = dayOffset <= 1
        ? dayLabel(day)
        : DateFormat('EEEE, d MMM').format(day);
    return _Glass(
      radius: 28,
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onEarlier,
                  tooltip: Txt.earlierDay,
                  icon: const Icon(Icons.chevron_left_rounded, size: 30),
                ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onLater,
                  tooltip: Txt.laterDay,
                  icon: const Icon(Icons.chevron_right_rounded, size: 30),
                ),
              ],
            ),
            if (loading)
              const Positioned(
                left: 24,
                right: 24,
                bottom: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom card: when and where the selected point is, how far through the
/// day it is, and the joystick.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.fixes,
    required this.pos,
    required this.moving,
    required this.color,
    required this.onStick,
    required this.onStep,
  });

  final List<LocationFix> fixes;
  final double pos;
  final bool moving;
  final Color color;
  final ValueChanged<double> onStick;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final has = fixes.isNotEmpty;
    final cur = has ? fixes[pos.round()] : null;
    final fmt = DateFormat.jm();
    final progress = fixes.length > 1 ? pos / (fixes.length - 1) : 0.0;

    return _Glass(
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  cur == null ? '–' : fmt.format(cur.timestamp),
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (cur != null && (cur.velocityKmh ?? 0) >= 8)
                  _Pill(
                    icon: Icons.speed_rounded,
                    text: Txt.kmH(cur.velocityKmh!.round()),
                    color: color,
                  ),
                if (cur?.battery != null) ...[
                  const SizedBox(width: 6),
                  _Pill(
                    icon: cur!.charging == true
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_std_rounded,
                    text: '${cur.battery}%',
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 22,
              child: cur == null ? null : _Address(fix: cur, moving: moving),
            ),
            const SizedBox(height: 10),
            // How far through the day.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: has ? progress : 0,
                minHeight: 5,
                color: color,
                backgroundColor: color.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  has ? fmt.format(fixes.first.timestamp) : '',
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  has ? fmt.format(fixes.last.timestamp) : '',
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: fixes.length < 2,
              child: Opacity(
                opacity: fixes.length < 2 ? 0.4 : 1,
                child: HistoryJoystick(
                  color: color,
                  onChanged: onStick,
                  onStep: onStep,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The street address, looked up with the phone's own geocoder (free, cached)
/// only once the point stops moving.
class _Address extends StatelessWidget {
  const _Address({required this.fix, required this.moving});
  final LocationFix fix;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final cached = AddressLookup.cached(fix.lat, fix.lon);
    Widget text(String s) =>
        Text(s, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (cached != null) return text(cached);
    if (moving) return text(timeAgo(fix.timestamp));
    return FutureBuilder<String?>(
      key: ValueKey('${fix.lat},${fix.lon}'),
      future: AddressLookup.lookup(fix.lat, fix.lon),
      builder: (_, s) => text(
        s.connectionState == ConnectionState.done
            ? (s.data ??
                  '${fix.lat.toStringAsFixed(5)}, ${fix.lon.toStringAsFixed(5)}')
            : Txt.findingAddress,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Glass(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Frosted card floating on the map, like the screenshots.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, required this.radius});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withOpacity(0.94),
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
