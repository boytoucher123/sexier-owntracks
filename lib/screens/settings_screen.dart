// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../services/mqtt_service.dart';
import '../services/platform_services.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/connection_form.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
                            s.displayName.isEmpty
                                ? s.deviceName
                                : s.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Edit name and photo',
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

          // ---- Sharing
          _Section(
            'Location sharing',
            children: [
              SwitchListTile(
                secondary: Icon(
                  s.sharingLocation
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: s.sharingLocation ? FlockColors.online : null,
                ),
                title: const Text('Share my location'),
                subtitle: Text(
                  s.sharingLocation
                      ? 'Your family can see where you are'
                      : 'Paused: your family sees your last spot',
                ),
                value: s.sharingLocation,
                onChanged: (v) =>
                    app.updateSettings(s.copyWith(sharingLocation: v)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: SegmentedButton<TrackingMode>(
                  segments: const [
                    ButtonSegment(
                      value: TrackingMode.batterySaver,
                      label: Text('Saver'),
                    ),
                    ButtonSegment(
                      value: TrackingMode.balanced,
                      label: Text('Balanced'),
                    ),
                    ButtonSegment(
                      value: TrackingMode.precise,
                      label: Text('Precise'),
                    ),
                  ],
                  selected: {s.trackingMode},
                  onSelectionChanged: s.sharingLocation
                      ? (v) => app.updateSettings(
                          s.copyWith(trackingMode: v.first),
                        )
                      : null,
                  showSelectedIcon: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Text(switch (s.trackingMode) {
                  TrackingMode.batterySaver =>
                    'Updates when you move about 500 m. Easiest on battery.',
                  TrackingMode.balanced =>
                    'Updates every ~100 m of movement. Recommended.',
                  TrackingMode.precise =>
                    'Frequent, exact updates. Uses noticeably more battery.',
                }, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),

          // ---- Map
          _Section('Map', children: [_MapChoice(app: app)]),

          // ---- Connection
          _Section(
            'Connection',
            children: [
              ListTile(
                leading: _statusDot(app.mqtt.status.value),
                title: Text(_statusText(app.mqtt.status.value)),
                subtitle: Text(
                  app.mqtt.lastError.value ?? '${s.host}:${s.port}',
                ),
                trailing: TextButton(
                  onPressed: () => app.updateSettings(s, reconnect: true),
                  child: const Text('Reconnect'),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.dns_rounded),
                title: const Text('Server & login'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _ServerSettingsPage(),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.timeline_rounded),
                title: const Text('Location history'),
                subtitle: Text(s.hasRecorder ? s.recorderUrl : 'Not set up'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _HistorySettingsPage(),
                  ),
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
                  title: const Text('Advanced'),
                  subtitle: const Text('You shouldn\'t need these'),
                  children: [
                    _InfoRow('Publishes to', s.ownTopic),
                    _InfoRow('Listens to', '${s.baseTopic}/${s.username}/+'),
                    _InfoRow('Client ID', app.clientId),
                    ListTile(
                      title: const Text('Keep-alive'),
                      subtitle: Text('${s.keepAliveSeconds} seconds'),
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
                      title: const Text('Send my location now'),
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
            label: const Text('Sign out and reset'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Flock · works with OwnTracks',
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
    ConnectionStatus.connected => 'Connected',
    ConnectionStatus.connecting => 'Connecting…',
    ConnectionStatus.disconnected => 'Offline',
    ConnectionStatus.error => 'Can\'t connect',
  };

  Future<void> _confirmSignOut(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This removes your server details and stops sharing your location from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FlockColors.danger,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
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

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return FutureBuilder<bool>(
      future: MapAvailability.googleMapsAvailable(),
      builder: (context, snap) {
        final google = snap.data ?? false;
        return Column(
          children: [
            RadioGroup<MapProvider>(
              groupValue: s.mapProvider,
              onChanged: (v) => _choose(context, v!),
              child: Column(
                children: [
                  const RadioListTile<MapProvider>(
                    value: MapProvider.standard,
                    title: Text('Standard'),
                    subtitle: Text(
                      'OpenStreetMap. Free, no Google account needed.',
                    ),
                  ),
                  RadioListTile<MapProvider>(
                    value: MapProvider.google,
                    enabled: google,
                    title: const Text('Google Maps'),
                    subtitle: Text(
                      google
                          ? 'Familiar Google look. Map views go through Google.'
                          : 'Not available in this build (no Google Maps key).',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _choose(BuildContext context, MapProvider v) async {
    if (v == MapProvider.google &&
        app.settings.mapProvider != MapProvider.google) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use Google Maps?'),
          content: const Text(
            'Google Maps loads map tiles from Google, so Google can see which areas '
            'you look at. Your family\'s locations still only go to your own server.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use Google Maps'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await app.updateSettings(app.settings.copyWith(mapProvider: v));
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
      maxWidth: 1024,
      maxHeight: 1024,
      preferredCameraDevice: CameraDevice.front,
    );
    if (x == null) return;
    await app.setMyPhoto(await x.readAsBytes());
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
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Library'),
              ),
              if (face != null)
                TextButton(
                  onPressed: () async {
                    await app.setMyPhoto(null);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tid,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Initials',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- server --

class _ServerSettingsPage extends StatefulWidget {
  const _ServerSettingsPage();
  @override
  State<_ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<_ServerSettingsPage> {
  late final AppState app = context.read<AppState>();
  late AppSettings _draft = app.settings;
  late final _device = TextEditingController(text: app.settings.deviceName);

  @override
  void dispose() {
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server & login')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ConnectionForm(
            initial: _draft,
            onTest: app.testConnection,
            onChanged: (s) => setState(
              () => _draft = s.copyWith(deviceName: _draft.deviceName),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _device,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Device name',
              helperText: 'Changing this makes you appear as a new person',
            ),
            onChanged: (v) => setState(
              () =>
                  _draft = _draft.copyWith(deviceName: sanitizeTopicSegment(v)),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                _draft.hasConnectionDetails && _draft.deviceName.isNotEmpty
                ? () async {
                    await app.updateSettings(_draft, reconnect: true);
                    if (context.mounted) Navigator.pop(context);
                  }
                : null,
            child: const Text('Save and reconnect'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- history --

class _HistorySettingsPage extends StatefulWidget {
  const _HistorySettingsPage();
  @override
  State<_HistorySettingsPage> createState() => _HistorySettingsPageState();
}

class _HistorySettingsPageState extends State<_HistorySettingsPage> {
  late final AppState app = context.read<AppState>();
  late final _url = TextEditingController(text: app.settings.recorderUrl);
  late final _user = TextEditingController(text: app.settings.recorderUsername);
  late final _pass = TextEditingController(text: app.settings.recorderPassword);
  bool _testing = false;
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  AppSettings get _draft => app.settings.copyWith(
    recorderUrl: _url.text.trim(),
    recorderUsername: _user.text.trim(),
    recorderPassword: _pass.text,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location history')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'History comes from the OwnTracks Recorder on your server. Enter its web '
            'address. Leave the login blank to use your normal username and password.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Recorder address',
              hintText: 'https://tracking.example.com/owntracks',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password (optional)'),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _testing
                ? null
                : () async {
                    setState(() => _testing = true);
                    final err = await app.testRecorder(_draft);
                    if (!mounted) return;
                    setState(() {
                      _testing = false;
                      _ok = err == null;
                      _message = err ?? 'History server found.';
                    });
                  },
            child: Text(_testing ? 'Checking…' : 'Check address'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    _ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: _ok ? FlockColors.online : FlockColors.danger,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await app.updateSettings(_draft);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
