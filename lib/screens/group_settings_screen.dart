// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../services/account_service.dart';
import '../services/mqtt_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../strings.dart';

/// Leader only: the group's server and how often everyone reports.
/// Members get these automatically; they never see a server setting.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key, required this.group});
  final Group group;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final GroupConfig? _initial = widget.group.config;
  late bool _editingServer = _initial == null || !_initial.standard;

  late final _host = TextEditingController(text: _own?.host ?? '');
  late final _port = TextEditingController(text: '${_own?.port ?? 8883}');
  late final _user = TextEditingController(text: _own?.username ?? '');
  late final _pass = TextEditingController(text: _own?.password ?? '');
  late final _history = TextEditingController(text: _own?.recorderUrl ?? '');
  late final _prefix = TextEditingController(
    text: _own?.topicPrefix ?? 'owntracks',
  );
  late final _ca = TextEditingController(text: _own?.ca ?? '');
  late bool _tls = _own?.tls ?? true;

  bool _saving = false;
  bool _testing = false;
  ConnectionTestResult? _test;
  String? _error;

  GroupConfig? get _own =>
      _initial != null && !_initial.standard ? _initial : null;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass, _history, _prefix, _ca]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The group as the server last described it (it changes after saving).
  Group _group(AppState app) =>
      app.account?.groups.where((g) => g.id == widget.group.id).firstOrNull ??
      widget.group;

  GroupConfig _draft(TrackingMode mode) => GroupConfig(
    standard: false,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    tls: _tls,
    ca: _ca.text.trim(),
    recorderUrl: _history.text.trim(),
    username: _user.text.trim(),
    password: _pass.text,
    topicPrefix: _prefix.text.trim().isEmpty
        ? 'owntracks'
        : _prefix.text.trim(),
    trackingMode: mode,
  );

  bool get _ready =>
      _host.text.trim().isNotEmpty &&
      _user.text.trim().isNotEmpty &&
      (int.tryParse(_port.text.trim()) ?? 0) > 0;

  Future<void> _setMode(AppState app, Group g, TrackingMode m) async {
    final err = await app.setGroupTracking(g, m);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _runTest(AppState app, TrackingMode mode) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _test = null;
    });
    final r = await app.testGroupServer(_draft(mode));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = r;
    });
  }

  Future<void> _save(AppState app, Group g, TrackingMode mode) async {
    FocusScope.of(context).unfocus();
    if (g.config?.standard == true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(Txt.moveToYourOwnServer),
          content: const Text(Txt.everyoneInTheGroupSwitches),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(Txt.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(Txt.move),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await app.setGroupServer(g, _draft(mode));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = err;
    });
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(Txt.savedEveryoneInTheGroup)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final g = _group(app);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final config = g.config;
    final mode = config?.trackingMode ?? TrackingMode.balanced;

    return Scaffold(
      appBar: AppBar(title: Text(Txt.settings(g.name))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            Txt.everyoneInGetsTheseSettings(g.name),
            style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // ---- Tracking
          Text(Txt.tracking, style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<TrackingMode>(
            segments: [
              for (final m in TrackingMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: config == null
                ? null
                : (v) => _setMode(app, g, v.first),
          ),
          const SizedBox(height: 6),
          Text(
            config == null ? Txt.setUpTheServerFirst : mode.description,
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),

          // ---- Server
          Text(Txt.server, style: t.titleMedium),
          const SizedBox(height: 8),
          if (config?.standard == true && !_editingServer) ...[
            Card(
              color: FlockColors.online.withOpacity(0.08),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: FlockColors.online),
                    SizedBox(width: 12),
                    Expanded(child: Text(Txt.runsOnThisAppS)),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _editingServer = true),
              child: const Text(Txt.useYourOwnServerInstead),
            ),
          ] else ...[
            if (config == null)
              Card(
                color: FlockColors.warning.withOpacity(0.12),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(Txt.newGroupsBringTheirOwn),
                ),
              ),
            const SizedBox(height: 12),
            _field(
              _host,
              Txt.serverAddress,
              hint: Txt.eGMqttExampleCom,
              icon: Icons.dns_rounded,
              keyboard: TextInputType.url,
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _port,
                    Txt.port,
                    keyboard: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(Txt.secureTls),
                    value: _tls,
                    onChanged: (v) => setState(() {
                      _tls = v;
                      _test = null;
                    }),
                  ),
                ),
              ],
            ),
            _field(_user, Txt.groupLoginUsername, icon: Icons.person_rounded),
            _field(
              _pass,
              Txt.groupLoginPassword,
              icon: Icons.key_rounded,
              obscure: true,
            ),
            _field(
              _history,
              Txt.historyAddressOptional,
              hint: Txt.historyAddressHint,
              icon: Icons.timeline_rounded,
              keyboard: TextInputType.url,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(Txt.moreOptions),
              children: [
                _field(_prefix, Txt.topicPrefix),
                _field(
                  _ca,
                  Txt.serverCertificateCaOptional,
                  hint: Txt.pasteThePemIfYour,
                  lines: 5,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_test != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      _test!.success
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: _test!.success
                          ? FlockColors.online
                          : FlockColors.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_test!.message)),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: FlockColors.danger),
                ),
              ),
            ListenableBuilder(
              listenable: Listenable.merge([_host, _port, _user]),
              builder: (context, _) => Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: _ready && !_testing
                          ? () => _runTest(app, mode)
                          : null,
                      child: Text(_testing ? Txt.testing : Txt.testConnection),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed: _ready && !_saving
                          ? () => _save(app, g, mode)
                          : null,
                      child: Text(_saving ? Txt.saving : Txt.save),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    IconData? icon,
    TextInputType? keyboard,
    bool obscure = false,
    int lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
        obscureText: obscure,
        autocorrect: false,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
        onChanged: (_) => setState(() => _test = null),
      ),
    );
  }
}
