// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../services/account_service.dart';
import '../services/mqtt_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/family_map.dart';
import 'group_settings_screen.dart';
import 'groups_screen.dart';
import 'photo_crop_screen.dart';
import '../strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text(Txt.settings2)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ---- Profile
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _editProfile(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Avatar(
                      colorKey: s.ownTopic,
                      initials: s.trackerId.isEmpty ? '?' : s.trackerId,
                      face: app.myFace,
                      size: 64,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.displayName.isEmpty ? s.username : s.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            Txt.editNameAndPhoto,
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Groups
          _Section(
            Txt.groups,
            children: [
              ListTile(
                leading: Badge(
                  isLabelVisible: (app.account?.waitingRequests ?? 0) > 0,
                  label: Text('${app.account?.waitingRequests ?? 0}'),
                  child: const Icon(Icons.groups_rounded),
                ),
                title: const Text(Txt.yourGroups),
                subtitle: Text(_groupsSummary(app)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const GroupsScreen())),
              ),
            ],
          ),

          // ---- Sharing
          _Section(
            Txt.locationSharing,
            children: [
              SwitchListTile(
                secondary: Icon(
                  s.sharingLocation
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: s.sharingLocation ? FlockColors.online : null,
                ),
                title: const Text(Txt.shareMyLocation),
                subtitle: Text(
                  s.sharingLocation
                      ? Txt.yourFriendsCanSeeWhere
                      : Txt.pausedFriendsSeeYourLast,
                ),
                value: s.sharingLocation,
                onChanged: (v) =>
                    app.updateSettings(s.copyWith(sharingLocation: v)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _GroupTrackingTile(app: app),
            ],
          ),

          // ---- Map
          _Section(Txt.map, children: [_MapChoice(app: app)]),

          // ---- Connection
          _Section(
            Txt.connection,
            children: [
              ListTile(
                leading: _statusDot(app.mqtt.status.value),
                title: Text(_statusText(app.mqtt.status.value)),
                subtitle: Text(
                  app.mqtt.lastError.value ??
                      (app.connection == null
                          ? Txt.noGroupServerYet
                          : '${app.connection!.host}:${app.connection!.port}'),
                ),
                trailing: TextButton(
                  onPressed: () => app.updateSettings(s, reconnect: true),
                  child: const Text(Txt.reconnect),
                ),
              ),
            ],
          ),

          // ---- Advanced (tucked away)
          _Section(
            '',
            children: [
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text(Txt.advanced),
                  subtitle: const Text(Txt.youShouldnTNeedThese),
                  children: [
                    _InfoRow(Txt.account, '@${s.username}'),
                    _InfoRow(
                      Txt.publishesTo,
                      app.connection?.ownTopic ?? Txt.nothingYet,
                    ),
                    _InfoRow(
                      Txt.server,
                      app.connection == null
                          ? Txt.noneYourGroupIsnT
                          : app.onOwnServer
                          ? Txt.sOwn(
                              app.connection!.host,
                              app.activeGroup!.name,
                            )
                          : Txt.accountServerLabel,
                    ),
                    ListTile(
                      leading: const Icon(Icons.key_rounded),
                      title: const Text(Txt.showMyLogin),
                      subtitle: const Text(Txt.toUseThisAccountIn),
                      enabled: app.connection != null,
                      onTap: () => _showLogin(context, app),
                    ),
                    ListTile(
                      title: const Text(Txt.keepAlive),
                      subtitle: Text(Txt.seconds(s.keepAliveSeconds)),
                      trailing: DropdownButton<int>(
                        value:
                            const [
                              30,
                              60,
                              120,
                              300,
                            ].contains(s.keepAliveSeconds)
                            ? s.keepAliveSeconds
                            : 60,
                        underline: const SizedBox.shrink(),
                        items: const [30, 60, 120, 300]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text('${v}s'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            app.updateSettings(s.copyWith(keepAliveSeconds: v)),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.my_location_rounded),
                      title: const Text(Txt.sendMyLocationNow),
                      onTap: () => app.location.reportNow('u'),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: FlockColors.danger,
            ),
            onPressed: () => _confirmSignOut(context, app),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(Txt.signOutOfThisPhone),
          ),
          if (s.hasAccount)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: FlockColors.danger),
              onPressed: () => _confirmDelete(context, app),
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text(Txt.deleteMyAccount),
            ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              Txt.flockWorksWithOwntracks,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(ConnectionStatus st) {
    final c = switch (st) {
      ConnectionStatus.connected => FlockColors.online,
      ConnectionStatus.connecting => FlockColors.warning,
      ConnectionStatus.disconnected => Colors.grey,
      ConnectionStatus.error => FlockColors.danger,
    };
    return Icon(Icons.circle, color: c, size: 14);
  }

  String _statusText(ConnectionStatus st) => switch (st) {
    ConnectionStatus.connected => Txt.connected,
    ConnectionStatus.connecting => Txt.connecting,
    ConnectionStatus.disconnected => Txt.offline,
    ConnectionStatus.error => Txt.canTConnect,
  };

  static String _groupsSummary(AppState app) {
    final a = app.account;
    if (a == null) return app.accountError ?? Txt.loading;
    final names = [for (final g in a.groups) g.name];
    final waiting = a.waitingRequests;
    final parts = [
      if (names.isNotEmpty) names.join(', ') else Txt.notInAGroupYet,
      if (waiting > 0) Txt.waitingToJoin(waiting),
      if (a.pending.isNotEmpty) Txt.waitingOnToLetYou(a.pending.length),
    ];
    return parts.join(' · ');
  }

  Future<void> _showLogin(BuildContext context, AppState app) async {
    final c = app.connection;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Txt.showYourLogin),
        content: const Text(Txt.anyoneWithThisLoginCan),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Txt.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Txt.show),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final rows = <(String, String)>[
      (Txt.mode, 'MQTT'),
      (Txt.host, c.host),
      (Txt.port, '${c.port}'),
      (Txt.tls, c.useTls ? Txt.on : Txt.off),
      (Txt.usernameUserid, c.username),
      (Txt.password, c.password),
      (Txt.deviceId, c.deviceName),
      if (c.baseTopic != 'owntracks')
        (Txt.publishTopic, '${c.baseTopic}/%u/%d'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            const ListTile(
              title: Text(Txt.yourLogin),
              subtitle: Text(Txt.enterTheseInTheOther),
            ),
            for (final (k, v) in rows)
              ListTile(
                dense: true,
                title: Text(k),
                subtitle: SelectableText(
                  v,
                  style: const TextStyle(fontSize: 16),
                ),
                trailing: IconButton(
                  tooltip: Txt.copy,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => Clipboard.setData(ClipboardData(text: v)),
                ),
              ),
            if (c.caPem.isNotEmpty)
              ListTile(
                title: const Text(Txt.serverCertificate),
                subtitle: const Text(Txt.thisServerUsesItsOwn),
                trailing: IconButton(
                  tooltip: Txt.copyCertificate,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: c.caPem)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Txt.deleteYourAccount),
        content: const Text(Txt.youLeaveAllYourGroups),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Txt.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FlockColors.danger,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Txt.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await app.deleteAccount();
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _confirmSignOut(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Txt.signOut),
        content: const Text(Txt.thisPhoneStopsSharingYour),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Txt.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FlockColors.danger,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Txt.signOut2),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      await app.signOut();
    }
  }

  void _editProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProfileSheet(),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(label),
    subtitle: SelectableText(
      value,
      style: const TextStyle(fontFamily: 'monospace'),
    ),
  );
}

class _MapChoice extends StatelessWidget {
  const _MapChoice({required this.app});
  final AppState app;

  static const _labels = {
    MapStyle.satellite: (Txt.satellite, Icons.satellite_alt_rounded),
    MapStyle.streets: (Txt.streets, Icons.map_rounded),
    MapStyle.terrain: (Txt.terrain, Icons.terrain_rounded),
    MapStyle.dark: (Txt.dark, Icons.dark_mode_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final google = app.googleMapsAvailable;
    final provider = app.mapProvider;
    final styles = mapStylesFor(provider);
    final style = effectiveMapStyle(provider, s.mapStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final st in styles)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(_labels[st]!.$2, size: 18),
                  label: Text(_labels[st]!.$1),
                  selected: st == style,
                  onSelected: (_) =>
                      app.updateSettings(app.settings.copyWith(mapStyle: st)),
                ),
            ],
          ),
        ),
        RadioGroup<MapProvider>(
          groupValue: provider,
          onChanged: (v) =>
              app.updateSettings(app.settings.copyWith(mapProvider: v)),
          child: Column(
            children: [
              RadioListTile<MapProvider>(
                value: MapProvider.google,
                enabled: google,
                title: const Text(Txt.googleMaps),
                subtitle: Text(
                  google
                      ? Txt.theFamiliarGoogleLookWith
                      : Txt.notAvailableInThisBuild,
                ),
              ),
              const RadioListTile<MapProvider>(
                value: MapProvider.standard,
                title: Text(Txt.openstreetmap),
                subtitle: Text(Txt.noGoogleInvolvedSatellitePhotos),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- profile --

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final AppState app = context.read<AppState>();
  late final _name = TextEditingController(text: app.settings.displayName);
  late final _tid = TextEditingController(text: app.settings.trackerId);

  @override
  void dispose() {
    _name.dispose();
    _tid.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(
      source: src,
      maxWidth: 2048,
      maxHeight: 2048,
      preferredCameraDevice: CameraDevice.front,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    final cropped = await PhotoCropScreen.open(context, bytes);
    if (cropped == null) return;
    await app.setMyPhoto(cropped);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final face = context.watch<AppState>().myFace;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Avatar(
              colorKey: app.settings.ownTopic,
              initials: _tid.text.isEmpty ? '?' : _tid.text.toUpperCase(),
              face: face,
              size: 96,
              enlargeable: true,
              label: Txt.yourPhoto,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text(Txt.camera),
              ),
              TextButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text(Txt.library),
              ),
              if (face != null)
                TextButton(
                  onPressed: () async {
                    await app.setMyPhoto(null);
                    if (mounted) setState(() {});
                  },
                  child: const Text(Txt.remove2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: Txt.yourName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tid,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: Txt.initials,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await app.updateSettings(
                app.settings.copyWith(
                  displayName: _name.text.trim(),
                  trackerId: _tid.text.trim().toUpperCase(),
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(Txt.save),
          ),
        ],
      ),
    );
  }
}

/// Your tracking level. The group's leader sets the default; you can pick
/// your own.
class _GroupTrackingTile extends StatelessWidget {
  const _GroupTrackingTile({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = app.activeGroup;
    final mode = app.connection?.trackingMode;
    final mine = app.settings.myTracking;
    return ListTile(
      leading: const Icon(Icons.speed_rounded),
      title: Text(mode == null ? Txt.tracking : Txt.tracking3(mode.label)),
      subtitle: Text(
        g == null
            ? Txt.joinOrStartAGroup
            : g.config == null
            ? Txt.isnTSetUpYet2(g.name)
            : mine == null
            ? Txt.setByFor(
                mode!.description,
                g.isLeader ? Txt.you : g.leaderName,
                g.name,
              )
            : mode!.description,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: g?.config == null ? null : () => _pick(context, g!),
    );
  }

  void _pick(BuildContext context, Group g) {
    final def = app.groupTracking ?? TrackingMode.balanced;
    final mine = app.settings.myTracking;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget option(TrackingMode? m, String title, String sub) => ListTile(
          title: Text(title),
          subtitle: Text(sub),
          trailing: mine == m ? const Icon(Icons.check_rounded) : null,
          onTap: () {
            Navigator.pop(ctx);
            app.setMyTracking(m);
          },
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  Txt.yourTracking,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              option(
                null,
                Txt.groupDefault(def.label),
                Txt.groupDefaultBy(g.isLeader ? Txt.you : g.leaderName, g.name),
              ),
              for (final m in TrackingMode.values)
                option(m, m.label, m.description),
              if (g.isLeader)
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text(Txt.changeGroupDefault),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupSettingsScreen(group: g),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
