// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/server_config.dart';
import '../models/person.dart';
import '../services/platform_services.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/day_track.dart';
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

/// Minutes of the day per second for a joystick push: a few minutes a
/// second near the centre, the whole day in about ten seconds at the edge.
@visibleForTesting
double historyMinutesPerSecond(double push) => historySpeed(push) * 3;

/// "Daily history": one person's day on the map, with a joystick that moves
/// a clock through the day. The map shows where they were at that moment.
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
  DayTrack _track = DayTrack(const []);

  /// Points that get a dot (stays always do; close-together reports don't).
  List<int> _dots = const [];

  late DateTime _dayStart = _midnight(0);
  late DateTime _dayEnd = DateTime.now();

  /// The moment being looked at.
  late DateTime _t = DateTime.now();
  double _stick = 0; // joystick push, -1..1

  static const _topInset = 84.0;
  static const _panelHeight = 250.0;

  static DateTime _midnight(int daysAgo) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - daysAgo);
  }

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
    final start = _midnight(day);
    final end = day == 0
        ? DateTime.now()
        : _midnight(day - 1).subtract(const Duration(seconds: 1));
    setState(() {
      _dayOffset = day;
      _dayStart = start;
      _dayEnd = end;
      _loading = true;
      _error = null;
    });
    try {
      final fixes = await context.read<AppState>().history(
        widget.person,
        start,
        end,
      );
      if (!mounted || req != _request) return;
      final track = DayTrack(fixes);
      setState(() {
        _track = track;
        _dots = _dotIndices(track);
        // Start at the latest moment there's data for.
        _t = day == 0 ? end : (track.isEmpty ? end : track.points.last.end);
        _loading = false;
      });
      if (!track.isEmpty) {
        _map.fit(track.points.map((p) => p.pos).toList());
      }
    } on Object catch (e) {
      if (!mounted || req != _request) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _track = DayTrack(const []);
        _dots = const [];
      });
    }
  }

  static List<int> _dotIndices(DayTrack track) {
    final out = <int>[];
    for (var i = 0; i < track.points.length; i++) {
      final p = track.points[i];
      final isEnd = i == 0 || i == track.points.length - 1;
      if (isEnd ||
          p.isStay ||
          metersBetween(track.points[out.last].pos, p.pos) >= 25) {
        out.add(i);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ movement --

  void _setStick(double v) {
    _stick = v;
    if (v != 0 && !_ticker.isActive && !_track.isEmpty) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (v == 0 && _ticker.isActive) {
      _ticker.stop();
      setState(() {}); // look up the address now it's still
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final speed = historyMinutesPerSecond(_stick);
    if (speed == 0) return;
    final ms = (_stick.sign * speed * 60000 * dt).round();
    var next = _t.add(Duration(milliseconds: ms));
    if (next.isBefore(_dayStart)) next = _dayStart;
    if (next.isAfter(_dayEnd)) next = _dayEnd;
    if (next == _t) return;
    // A tick each time a report is passed, when slow enough to feel it.
    if (speed < 20 && _track.indexAt(next) != _track.indexAt(_t)) {
      HapticFeedback.selectionClick();
    }
    setState(() => _t = next);
    // Follow the pin while it moves.
    final m = _track.at(next);
    if (m != null) _map.track(m.pos);
  }

  /// Taps on the joystick's sides: the previous or next dot.
  void _step(int dir) {
    if (_dots.isEmpty) return;
    final pts = _track.points;
    DateTime? target;
    if (dir < 0) {
      for (final i in _dots.reversed) {
        if (pts[i].start.isBefore(_t)) {
          target = pts[i].start;
          break;
        }
      }
    } else {
      for (final i in _dots) {
        if (pts[i].start.isAfter(_t)) {
          target = pts[i].start;
          break;
        }
      }
    }
    if (target == null) return;
    setState(() => _t = target!);
    _follow(force: true);
  }

  void _jumpToDot(int dot) {
    _setStick(0);
    setState(() => _t = _track.points[_dots[dot]].start);
    HapticFeedback.selectionClick();
    _follow(force: true);
  }

  /// Keep the moving avatar on screen without fighting the person's own pans.
  void _follow({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastFollow).inMilliseconds < 250) return;
    _lastFollow = now;
    final m = _track.at(_t);
    if (m != null) _map.ensureVisible(m.pos);
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = widget.person;
    final color = FlockColors.forKey(p.topic);
    final media = MediaQuery.of(context);
    final moment = _track.at(_t);

    // The person's pin, where they were at that moment.
    final pin = moment == null
        ? null
        : Person(
            topic: p.topic,
            user: p.user,
            device: p.device,
            cardName: p.cardName,
            face: p.face,
            trackerId: p.trackerId,
            last: LocationFix(
              lat: moment.pos.latitude,
              lon: moment.pos.longitude,
              timestamp: _t,
            ),
          );
    var selectedDot = -1;
    if (_stick == 0 &&
        moment?.point != null &&
        !_t.isAfter(moment!.point!.end)) {
      selectedDot = _dots.indexOf(_track.points.indexOf(moment.point!));
    }
    final guess =
        moment != null &&
        (moment.state == TrackState.gap || moment.state == TrackState.before);

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
              trail: [for (final pt in _track.points) pt.pos],
              trailGaps: _track.gaps,
              trailColor: color,
              nodes: [for (final i in _dots) _track.points[i].pos],
              selectedNode: selectedDot < 0 ? null : selectedDot,
              onNodeTap: _jumpToDot,
              markStale: false,
              // Moving: drawn over the map so it glides. Still: the map
              // draws it, so it stays put when zooming.
              floatingTopic: _stick != 0 ? p.topic : null,
              floatingDimmed: guess,
              places: app.places,
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
          if (!_loading && (_error != null || _track.isEmpty))
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
              t: _t,
              moment: moment,
              dayStart: _dayStart,
              dayEnd: _dayEnd,
              today: _dayOffset == 0,
              moving: _stick != 0,
              enabled: !_track.isEmpty,
              color: color,
              onStick: _setStick,
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

/// Bottom card: the time being looked at, where they were then, how far
/// through the day it is, and the joystick.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.t,
    required this.moment,
    required this.dayStart,
    required this.dayEnd,
    required this.today,
    required this.moving,
    required this.enabled,
    required this.color,
    required this.onStick,
    required this.onStep,
  });

  final DateTime t;
  final TrackMoment? moment;
  final DateTime dayStart;
  final DateTime dayEnd;
  final bool today;
  final bool moving;
  final bool enabled;
  final Color color;
  final ValueChanged<double> onStick;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.jm();
    final m = moment;
    final point = m?.point;
    final fix = point?.fix;
    final atNow = today && dayEnd.difference(this.t).inSeconds.abs() < 60;
    final span = dayEnd.difference(dayStart).inMilliseconds;
    final progress = span <= 0
        ? 0.0
        : (this.t.difference(dayStart).inMilliseconds / span).clamp(0.0, 1.0);

    // Last stay of today still going: "since".
    final stillThere =
        today &&
        point != null &&
        point.isStay &&
        (m!.state == TrackState.after || m.state == TrackState.staying) &&
        dayEnd.difference(point.end) < const Duration(minutes: 30);

    String? detail;
    var detailMuted = false;
    switch (m?.state) {
      case null:
        break;
      case TrackState.before:
        detail = Txt.noDataBefore(fmt.format(point!.start));
        detailMuted = true;
      case TrackState.staying:
        detail = stillThere
            ? Txt.hereSince(fmt.format(point.start))
            : Txt.stayedFromTo(fmt.format(point!.start), fmt.format(point.end));
      case TrackState.moving:
        detail = point != null && point.end == this.t
            ? Txt.reportAt(fmt.format(point.end))
            : Txt.betweenReports;
      case TrackState.gap:
        detail = Txt.noDataFromTo(fmt.format(m!.from!), fmt.format(m.to!));
        detailMuted = true;
      case TrackState.after:
        detail = stillThere
            ? Txt.hereSince(fmt.format(point.start))
            : Txt.lastReportAt(fmt.format(point!.end));
        detailMuted = !stillThere;
    }

    final where = m == null
        ? null
        : m.state == TrackState.gap
        ? Text(
            Txt.locationUnknown,
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        : _Address(
            fix: LocationFix(
              lat: m.pos.latitude,
              lon: m.pos.longitude,
              timestamp: this.t,
            ),
            moving: moving,
          );

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
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      atNow ? Txt.now : fmt.format(this.t),
                      style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (point != null &&
                    point.isStay &&
                    (m!.state == TrackState.staying || stillThere))
                  _Pill(
                    icon: Icons.timer_outlined,
                    text: formatDuration(
                      (stillThere ? dayEnd : point.end).difference(point.start),
                    ),
                    color: color,
                  ),
                if (m?.state == TrackState.moving &&
                    (fix?.velocityKmh ?? 0) >= 8)
                  _Pill(
                    icon: Icons.speed_rounded,
                    text: Txt.kmH(fix!.velocityKmh!.round()),
                    color: color,
                  ),
                if (fix?.battery != null) ...[
                  const SizedBox(width: 6),
                  _Pill(
                    icon: fix!.charging == true
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_std_rounded,
                    text: '${fix.battery}%',
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(height: 22, child: where),
            SizedBox(
              height: 18,
              child: detail == null
                  ? null
                  : Row(
                      children: [
                        if (detailMuted) ...[
                          Icon(
                            Icons
                                .signal_cellular_connected_no_internet_0_bar_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(
                              color: detailMuted ? cs.onSurfaceVariant : color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            // Where in the day this is, midnight to midnight.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: color,
                backgroundColor: color.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  fmt.format(dayStart),
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  today ? Txt.now : fmt.format(dayEnd),
                  style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: !enabled,
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
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
    Widget text(String s) =>
        Text(s, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    final place = context.read<AppState>().placeFor(fix.latLng);
    if (place != null) return text(Txt.atPlace(place.name));
    final cached = AddressLookup.cached(fix.lat, fix.lon);
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
