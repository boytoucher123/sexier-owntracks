// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../services/mqtt_service.dart';
import '../theme.dart';

/// What the user typed in the server box, split into its parts.
class ParsedHost {
  const ParsedHost(this.host, {this.port, this.tls, this.webSocket});
  final String host;
  final int? port;
  final bool? tls;
  final bool? webSocket;
}

/// Accepts whatever people paste: `mqtt.example.com`, `example.com:1883`,
/// `mqtts://example.com:8883`, `wss://example.com/mqtt` ...
ParsedHost parseHostInput(String input) {
  var s = input.trim();
  bool? tls;
  bool? ws;
  final scheme = RegExp(r'^([a-zA-Z]+)://').firstMatch(s);
  if (scheme != null) {
    switch (scheme.group(1)!.toLowerCase()) {
      case 'mqtts':
      case 'ssl':
      case 'tls':
        tls = true;
        ws = false;
      case 'mqtt':
      case 'tcp':
        tls = false;
        ws = false;
      case 'wss':
        tls = true;
        ws = true;
      case 'ws':
        tls = false;
        ws = true;
    }
    // Websocket URLs keep their scheme and path; mqtt_client needs them.
    if (ws != true) s = s.substring(scheme.end);
  }
  if (ws == true) {
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      return ParsedHost(s, tls: tls, webSocket: true);
    }
    return ParsedHost(
      '${uri.scheme}://${uri.host}${uri.path}',
      port: uri.hasPort ? uri.port : null,
      tls: tls,
      webSocket: true,
    );
  }
  s = s.split('/').first;
  final m = RegExp(r'^(.+):(\d{1,5})$').firstMatch(s);
  if (m != null) {
    return ParsedHost(
      m.group(1)!,
      port: int.parse(m.group(2)!),
      tls: tls,
      webSocket: ws,
    );
  }
  return ParsedHost(s, tls: tls, webSocket: ws);
}

/// Server address, login, and a big friendly "Test connection" button.
class ConnectionForm extends StatefulWidget {
  const ConnectionForm({
    super.key,
    required this.initial,
    required this.onTest,
    required this.onChanged,
    this.onTestResult,
  });

  final AppSettings initial;
  final Future<ConnectionTestResult> Function(AppSettings) onTest;
  final ValueChanged<AppSettings> onChanged;
  final ValueChanged<ConnectionTestResult?>? onTestResult;

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  late final _host = TextEditingController(text: widget.initial.host);
  late final _user = TextEditingController(text: widget.initial.username);
  late final _pass = TextEditingController(text: widget.initial.password);
  late final _port = TextEditingController(text: '${widget.initial.port}');
  late final _topic = TextEditingController(text: widget.initial.baseTopic);
  late bool _tls = widget.initial.useTls;
  late bool _ws = widget.initial.useWebSocket;
  late bool _untrusted = widget.initial.allowUntrustedCertificates;
  bool _portTouched = false;
  bool _showPass = false;
  bool _testing = false;
  ConnectionTestResult? _result;

  @override
  void initState() {
    super.initState();
    // If the saved port isn't the default for the TLS setting, the user chose it.
    _portTouched = widget.initial.port != (_tls ? 8883 : 1883);
  }

  @override
  void dispose() {
    for (final c in [_host, _user, _pass, _port, _topic]) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings _current() {
    final parsed = parseHostInput(_host.text);
    return widget.initial.copyWith(
      host: parsed.host,
      port: int.tryParse(_port.text.trim()) ?? (_tls ? 8883 : 1883),
      useTls: _tls,
      useWebSocket: _ws,
      username: _user.text.trim(),
      password: _pass.text,
      baseTopic: _topic.text.trim().isEmpty ? 'owntracks' : _topic.text.trim(),
      allowUntrustedCertificates: _untrusted,
    );
  }

  void _changed() {
    if (_result != null) {
      _result = null;
      widget.onTestResult?.call(null);
    }
    widget.onChanged(_current());
    setState(() {});
  }

  void _onHostChanged(String v) {
    final p = parseHostInput(v);
    if (p.tls != null) _tls = p.tls!;
    if (p.webSocket != null) _ws = p.webSocket!;
    if (p.port != null) {
      _port.text = '${p.port}';
      _portTouched = true;
    } else if (!_portTouched) {
      _port.text = _ws ? (_tls ? '443' : '80') : (_tls ? '8883' : '1883');
    }
    _changed();
  }

  void _onTlsChanged(bool v) {
    _tls = v;
    if (!_portTouched) {
      _port.text = _ws ? (v ? '443' : '80') : (v ? '8883' : '1883');
    }
    _changed();
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _result = null;
    });
    final r = await widget.onTest(_current());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = r;
    });
    widget.onTestResult?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canTest =
        _host.text.trim().isNotEmpty && _user.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _host,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'e.g. tracking.example.com',
            prefixIcon: Icon(Icons.dns_rounded),
          ),
          onChanged: _onHostChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'The shared family login',
            prefixIcon: Icon(Icons.person_rounded),
          ),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: !_showPass,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _showPass
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
          onChanged: (_) => _changed(),
          onSubmitted: (_) => canTest ? _test() : null,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Secure connection'),
          subtitle: const Text('Leave on unless your server says otherwise'),
          value: _tls,
          onChanged: _onTlsChanged,
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              'More options',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            children: [
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
                onChanged: (_) {
                  _portTouched = true;
                  _changed();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _topic,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Topic prefix',
                  helperText: 'Almost always "owntracks"',
                ),
                onChanged: (_) => _changed(),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Connect over WebSockets'),
                value: _ws,
                onChanged: (v) {
                  _ws = v;
                  if (!_portTouched) {
                    _port.text = v
                        ? (_tls ? '443' : '80')
                        : (_tls ? '8883' : '1883');
                  }
                  _changed();
                },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Allow self-signed certificate'),
                subtitle: const Text('Only if you run your own certificates'),
                value: _untrusted,
                onChanged: (v) {
                  _untrusted = v;
                  _changed();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: canTest && !_testing ? _test : null,
          icon: _testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.wifi_tethering_rounded),
          label: Text(_testing ? 'Testing…' : 'Test connection'),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _result == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(_result!.message),
                  padding: const EdgeInsets.only(top: 12),
                  child: _ResultCard(result: _result!),
                ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final ConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? FlockColors.online : FlockColors.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(result.message)),
        ],
      ),
    );
  }
}
