// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/person.dart';
import '../services/mqtt_service.dart';
import '../services/platform_services.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/avatar.dart';
import '../widgets/family_map.dart';
import 'groups_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _map = FamilyMapController();
  final _sheet = DraggableScrollableController();
  double _sheetFraction = _kSheetHalf;

  String? _selected;
  bool _didInitialFit = false;

  // Sheet stops. The lowest one is measured in pixels so it always shows
  // exactly the header plus one person, sitting clear of the gesture bar.
  // The others are fractions of the screen.
  static const _kPeekPx = 67.0 + 84; // grabber and title + one row
  static const _kSheetHalf = 0.45;
  static const _kSheetMax = 0.88;
  double _screenH = 800;
  double _bottomPad = 0;

  double get _sheetMin =>
      ((_kPeekPx + _bottomPad) / _screenH).clamp(0.1, _kSheetHalf - 0.05);

  // Kept as one list so the sheet doesn't see "new" stops on every rebuild,
  // which would make it reset mid-drag.
  List<double> _snaps = const [];
  List<double> get _snapSizes {
    final min = _sheetMin;
    if (_snaps.isEmpty || _snaps.first != min) {
      _snaps = [min, _kSheetHalf, _kSheetMax];
    }
    return _snaps;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    if (state == AppLifecycleState.resumed) app.onResume();
    if (state == AppLifecycleState.paused) app.onPause();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheet.addListener(() {
      if (!_sheet.isAttached) return;
      final s = _sheet.size;
      if ((s - _sheetFraction).abs() > 0.01) setState(() => _sheetFraction = s);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sheet.dispose();
    super.dispose();
  }

  void _select(Person p, {bool moveMap = true}) {
    setState(() {
      _selected = p.topic;
    });
    if (moveMap && p.last != null) _map.focus(p.last!.latLng);
    if (_sheet.isAttached && _sheet.size < _kSheetHalf - 0.01) {
      _sheet.animateTo(
        _kSheetHalf,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearSelection() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
    });
  }

  void _fitEveryone(List<Person> people) {
    _map.fit([
      for (final p in people)
        if (p.last != null) p.last!.latLng,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final people = app.people;
    final selected = _selected == null ? null : app.personByTopic(_selected!);
    final media = MediaQuery.of(context);
    _screenH = media.size.height;
    _bottomPad = media.viewPadding.bottom;
    final sheetPx = media.size.height * _sheetFraction;

    // On first data, frame everyone.
    if (!_didInitialFit && people.any((p) => p.hasLocation)) {
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitEveryone(people));
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FamilyMap(
              provider: app.mapProvider,
              style: app.settings.mapStyle,
              controller: _map,
              people: people,
              selectedTopic: _selected,
              onPersonTap: (p) => _select(p, moveMap: false),
              onMapTap: _clearSelection,
              bottomInset: sheetPx,
              topInset: media.padding.top + 56,
            ),
          ),

          // Top bar: status + settings.
          Positioned(
            top: media.padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _StatusChip(
                  status: app.mqtt.status.value,
                  error: app.mqtt.lastError.value,
                ),
                const Spacer(),
                _RoundButton(
                  icon: Icons.settings_rounded,
                  tooltip: 'Settings',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
          ),

          // Floating map buttons that ride on top of the sheet.
          Positioned(
            right: 16,
            bottom: sheetPx + 12,
            child: IgnorePointer(
              ignoring: _sheetFraction > 0.55,
              child: AnimatedOpacity(
                opacity: _sheetFraction > 0.55 ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: Column(
                  children: [
                    _RoundButton(
                      icon: Icons.groups_rounded,
                      tooltip: 'Show everyone',
                      onTap: () {
                        _clearSelection();
                        _fitEveryone(people);
                      },
                    ),
                    const SizedBox(height: 10),
                    _RoundButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Me',
                      onTap: () {
                        final me = people.where(app.isMe).firstOrNull;
                        if (me != null && me.hasLocation) {
                          _select(me);
                        } else {
                          app.location.reportNow('u');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _kSheetHalf,
            minChildSize: _sheetMin,
            maxChildSize: _kSheetMax,
            snap: true,
            snapSizes: _snapSizes,
            builder: (context, scroll) {
              return _SheetSurface(
                child: selected == null
                    ? _PeopleList(
                        scroll: scroll,
                        people: people,
                        app: app,
                        onTap: _select,
                      )
                    : _PersonDetail(
                        scroll: scroll,
                        person: selected,
                        app: app,
                        onBack: _clearSelection,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ chrome --

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 12,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.18),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: cs.surface,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.error});
  final ConnectionStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (FlockColors.online, 'Live'),
      ConnectionStatus.connecting => (FlockColors.warning, 'Connecting…'),
      ConnectionStatus.disconnected => (Colors.grey, 'Offline'),
      ConnectionStatus.error => (FlockColors.danger, 'Can\'t connect'),
    };
    return Material(
      color: cs.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: error == null
            ? null
            : () =>
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error!))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Pulse(
                color: color,
                active: status == ConnectionStatus.connected,
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _PulsePainter(widget.color, widget.active ? _c.value : 0),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (t > 0) {
      canvas.drawCircle(
        c,
        4 + 6 * t,
        Paint()..color = color.withOpacity(0.35 * (1 - t)),
      );
    }
    canvas.drawCircle(c, 4.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t || o.color != color;
}

// ------------------------------------------------------------- people list --

class _PeopleList extends StatelessWidget {
  const _PeopleList({
    required this.scroll,
    required this.people,
    required this.app,
    required this.onTap,
  });

  final ScrollController scroll;
  final List<Person> people;
  final AppState app;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = people.where(app.isMe).firstOrNull;
    final account = app.account;
    final waiting = account?.waitingRequests ?? 0;
    return ListView(
      controller: scroll,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        const _Grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Row(
            children: [
              Text('People', style: t.titleLarge),
              const SizedBox(width: 8),
              if (people.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${people.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              Badge(
                isLabelVisible: waiting > 0,
                label: Text('$waiting'),
                child: TextButton.icon(
                  onPressed: () => _openGroups(context),
                  icon: const Icon(Icons.groups_rounded),
                  label: const Text('Groups'),
                ),
              ),
            ],
          ),
        ),
        if (!app.settings.sharingLocation)
          const _Banner(
            icon: Icons.location_off_rounded,
            text: 'You\'re not sharing your location. Turn it on in Settings.',
          ),
        if (account != null)
          for (final g in account.groups)
            if (g.isLeader && g.requests.isNotEmpty)
              _Banner(
                icon: Icons.person_add_alt_1_rounded,
                text: g.requests.length == 1
                    ? '${g.requests.first.name} wants to join ${g.name}.'
                    : '${g.requests.length} people want to join ${g.name}.',
                onTap: () => _openGroups(context),
              ),
        if (account != null)
          for (final p in account.pending)
            _Banner(
              icon: Icons.hourglass_top_rounded,
              text: 'Waiting for ${p.leaderName} to let you into ${p.name}.',
              onTap: () => _openGroups(context),
            ),
        for (final p in people)
          _PersonRow(
            person: p,
            isMe: app.isMe(p),
            onTap: () => onTap(p),
            me: me,
          ),
        if (people.isEmpty || (people.length == 1 && me != null))
          _EmptyPeople(
            inGroup: account == null || account.groups.isNotEmpty,
            onGroups: () => _openGroups(context),
          ),
      ],
    );
  }
}

void _openGroups(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const GroupsScreen()));

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.inGroup, required this.onGroups});
  final bool inGroup;
  final VoidCallback onGroups;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Card(
        color: cs.primary.withOpacity(0.08),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onGroups,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    inGroup
                        ? 'No one else here yet. Share your group\'s code from '
                              'Groups so your friends can ask to join.'
                        : 'You\'re not in a group yet. Start one, or enter a '
                              'code someone sent you, in Groups.',
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Card(
        color: FlockColors.warning.withOpacity(0.15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: FlockColors.warning),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
                if (onTap != null) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.isMe,
    required this.onTap,
    this.me,
  });

  final Person person;
  final bool isMe;
  final Person? me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fix = person.last;
    final stale = fix != null && isStale(fix.timestamp);

    String? away;
    if (!isMe && fix != null && me?.last != null) {
      away = formatDistance(metersBetween(me!.last!.latLng, fix.latLng));
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Avatar.person(person, size: 52, dimmed: stale),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          person.name,
                          style: t.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(you)',
                          style: t.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (fix == null)
                    Text(
                      'No location yet',
                      style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    )
                  else
                    _AddressText(fix: fix, style: t.bodyMedium),
                  const SizedBox(height: 2),
                  if (fix != null)
                    Text(
                      [timeAgo(fix.timestamp), ?away].join(' · '),
                      style: t.bodySmall?.copyWith(
                        color: stale
                            ? FlockColors.warning
                            : cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (fix?.battery != null)
              _Battery(level: fix!.battery!, charging: fix.charging),
          ],
        ),
      ),
    );
  }
}

class _AddressText extends StatelessWidget {
  const _AddressText({required this.fix, this.style, this.maxLines = 1});
  final LocationFix fix;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cached = AddressLookup.cached(fix.lat, fix.lon);
    return FutureBuilder<String?>(
      initialData: cached,
      future: cached != null ? null : AddressLookup.lookup(fix.lat, fix.lon),
      builder: (context, snap) {
        final text =
            snap.data ??
            '${fix.lat.toStringAsFixed(4)}, ${fix.lon.toStringAsFixed(4)}';
        return Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.level, this.charging});
  final int level;
  final bool? charging;

  @override
  Widget build(BuildContext context) {
    final color = level <= 15
        ? FlockColors.danger
        : level <= 30
        ? FlockColors.warning
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = charging == true
        ? Icons.battery_charging_full_rounded
        : level > 85
        ? Icons.battery_full_rounded
        : level > 60
        ? Icons.battery_5_bar_rounded
        : level > 35
        ? Icons.battery_3_bar_rounded
        : level > 15
        ? Icons.battery_2_bar_rounded
        : Icons.battery_alert_rounded;
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        Text(
          '$level%',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- person detail --

class _PersonDetail extends StatelessWidget {
  const _PersonDetail({
    required this.scroll,
    required this.person,
    required this.app,
    required this.onBack,
  });

  final ScrollController scroll;
  final Person person;
  final AppState app;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fix = person.last;
    final isMe = app.isMe(person);
    final color = FlockColors.forKey(person.topic);

    return ListView(
      controller: scroll,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        const _Grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to everyone',
              ),
              Avatar.person(person, size: 56, enlargeable: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${person.name} (you)' : person.name,
                      style: t.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (fix != null)
                      Text(
                        timeAgo(fix.timestamp),
                        style: t.bodyMedium?.copyWith(
                          color: isStale(fix.timestamp)
                              ? FlockColors.warning
                              : cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (fix?.battery != null)
                _Battery(level: fix!.battery!, charging: fix.charging),
            ],
          ),
        ),
        if (fix != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Card(
              color: color.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AddressText(
                        fix: fix,
                        style: t.bodyLarge,
                        maxLines: 2,
                      ),
                    ),
                    if ((fix.velocityKmh ?? 0) >= 8)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Chip(
                          avatar: const Icon(
                            Icons.directions_car_rounded,
                            size: 16,
                          ),
                          label: Text('${fix.velocityKmh!.round()} km/h'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              _ActionButton(
                icon: Icons.refresh_rounded,
                label: isMe ? 'Update' : 'Refresh',
                onTap: () {
                  final ok = app.requestUpdate(person);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? (isMe
                                  ? 'Sending your location…'
                                  : 'Asked ${person.name}\'s phone for an update.')
                            : 'You\'re offline right now.',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.directions_rounded,
                label: 'Directions',
                onTap: fix == null
                    ? null
                    : () => launchUrl(
                        directionsUri(fix.lat, fix.lon),
                        mode: LaunchMode.externalApplication,
                      ),
              ),
              const SizedBox(width: 10),
              _ActionButton(
                icon: Icons.history_rounded,
                label: 'History',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(person: person),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.primary.withOpacity(0.10);
    final fg = cs.primary;
    return Expanded(
      child: Material(
        color: onTap == null ? cs.onSurface.withOpacity(0.05) : bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: onTap == null ? cs.onSurface.withOpacity(0.3) : fg,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: onTap == null ? cs.onSurface.withOpacity(0.3) : fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple Maps on iPhone, Google Maps everywhere else.
Uri directionsUri(double lat, double lon) => Platform.isIOS
    ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lon')
    : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
