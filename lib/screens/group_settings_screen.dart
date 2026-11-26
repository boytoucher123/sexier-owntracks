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
  // The group's server, shown as it is (for a standard group, the details
  // your account's server filled in).
  late final GroupConfig? _initial = widget.group.config;

  late final _host = TextEditingController(text: _initial?.host ?? '');
  late final _port = TextEditingController(text: '${_initial?.port ?? 8883}');
  late final _history = TextEditingController(
    text: _initial?.recorderUrl ?? '',
  );
  late final _prefix = TextEditingController(
    text: _initial?.topicPrefix ?? 'owntracks',
  );
  late final _ca = TextEditingController(text: _initial?.ca ?? '');
  late bool _tls = _initial?.tls ?? true;
  bool _more = false;

  bool _saving = false;
  bool _testing = false;
  ConnectionTestResult? _test;
  String? _error;

  /// Edited away from what the group has now.
  bool get _changed {
    final c = _initial;
    if (c == null) return true;
    return _host.text.trim() != c.host ||
        (int.tryParse(_port.text.trim()) ?? 0) != c.port ||
        _tls != c.tls ||
        _history.text.trim() != c.recorderUrl ||
        _prefix.text.trim() != c.topicPrefix ||
        _ca.text.trim() != c.ca.trim();
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _history, _prefix, _ca]) {
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
    topicPrefix: _prefix.text.trim().isEmpty
        ? 'owntracks'
        : _prefix.text.trim(),
    trackingMode: mode,
  );

  bool get _ready =>
      _host.text.trim().isNotEmpty &&
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
    if (g.config?.standard == true && _changed) {
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
          Card(
            color: (config == null ? FlockColors.warning : FlockColors.online)
                .withOpacity(0.10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    config == null
                        ? Icons.info_outline_rounded
                        : Icons.verified_rounded,
                    color: config == null
                        ? FlockColors.warning
                        : FlockColors.online,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      config == null
                          ? Txt.newGroupsBringTheirOwn
                          : config.standard
                          ? Txt.runsOnThisAppS
                          : Txt.runsOnYourOwnServer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...[
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
            _field(
              _history,
              Txt.historyAddressOptional,
              hint: Txt.historyAddressHint,
              icon: Icons.timeline_rounded,
              keyboard: TextInputType.url,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _more = !_more),
                icon: Icon(
                  _more ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                ),
                label: const Text(Txt.moreOptions),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _more
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
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
                    )
                  : const SizedBox(width: double.infinity),
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
              listenable: Listenable.merge([_host, _port]),
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
                      onPressed: _ready && _changed && !_saving
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
          alignLabelWithHint: lines > 1,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
        onChanged: (_) => setState(() => _test = null),
      ),
    );
  }
}
