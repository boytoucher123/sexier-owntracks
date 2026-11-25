// ignore_for_file: deprecated_member_use
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../services/location_service.dart';
import '../services/mqtt_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/connection_form.dart';
import 'photo_crop_screen.dart';

/// Welcome → Server → You → History → Location → done.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  late AppSettings _draft;
  Uint8List? _photo;
  bool _connectionOk = false;
  bool _finishing = false;

  static const _count = 5;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _draft = app.settings;
    _photo = app.myFace;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_page < _count - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    _pages.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final app = context.read<AppState>();
    await app.updateSettings(_draft);
    await app.setMyPhoto(_photo);
    await app.completeSetup();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_page > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _page / (_count - 1),
                          minHeight: 6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onNext: _next),
                  _ServerPage(
                    draft: _draft,
                    ok: _connectionOk,
                    onChanged: (s) => setState(() => _draft = s),
                    onResult: (r) =>
                        setState(() => _connectionOk = r?.success ?? false),
                    onNext: _next,
                  ),
                  _YouPage(
                    draft: _draft,
                    photo: _photo,
                    onChanged: (s) => setState(() => _draft = s),
                    onPhoto: (b) => setState(() => _photo = b),
                    onNext: _next,
                  ),
                  _HistoryPage(
                    draft: _draft,
                    onChanged: (s) => setState(() => _draft = s),
                    onNext: _next,
                  ),
                  _LocationPage(onFinish: _finish, finishing: _finishing),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.primary,
    this.secondary,
    this.icon,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget primary;
  final Widget? secondary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            children: [
              if (icon != null) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: cs.primary, size: 30),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Text(title, style: t.headlineMedium),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            children: [
              primary,
              if (secondary != null) ...[const SizedBox(height: 4), secondary!],
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- welcome --

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          const Spacer(),
          const _HeroCluster(),
          const SizedBox(height: 40),
          Text(
            'Stay close to\nyour people',
            textAlign: TextAlign.center,
            style: t.headlineLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'See where your friends are, check they got home safe, and look back '
            'at their day. On your own server, so it stays private.',
            textAlign: TextAlign.center,
            style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          FilledButton(onPressed: onNext, child: const Text('Get started')),
        ],
      ),
    );
  }
}

class _HeroCluster extends StatelessWidget {
  const _HeroCluster();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bubble(String i, String key, double size) =>
        Avatar(colorKey: key, initials: i, size: size);
    return SizedBox(
      width: 260,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  cs.primary.withOpacity(0.22),
                  cs.primary.withOpacity(0.0),
                ],
              ),
            ),
          ),
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary.withOpacity(0.25), width: 2),
            ),
          ),
          Positioned(top: 18, left: 40, child: bubble('MA', 'a', 64)),
          Positioned(top: 40, right: 30, child: bubble('JD', 'bb', 56)),
          Positioned(bottom: 20, left: 70, child: bubble('SK', 'cccc', 52)),
          Positioned(bottom: 34, right: 54, child: bubble('FD', 'dd', 60)),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: FlockColors.brand,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ server --

class _ServerPage extends StatelessWidget {
  const _ServerPage({
    required this.draft,
    required this.ok,
    required this.onChanged,
    required this.onResult,
    required this.onNext,
  });

  final AppSettings draft;
  final bool ok;
  final ValueChanged<AppSettings> onChanged;
  final ValueChanged<ConnectionTestResult?> onResult;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return _PageScaffold(
      icon: Icons.cloud_rounded,
      title: 'Connect to your server',
      subtitle: 'Whoever set up the server for your group can give you these details.',
      primary: FilledButton(
        onPressed: ok ? onNext : null,
        child: const Text('Continue'),
      ),
      secondary: ok || !draft.hasConnectionDetails
          ? null
          : TextButton(
              onPressed: onNext,
              child: const Text('Skip test and continue'),
            ),
      children: [
        ConnectionForm(
          initial: draft,
          onTest: app.testConnection,
          onChanged: onChanged,
          onTestResult: onResult,
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- you --

class _YouPage extends StatefulWidget {
  const _YouPage({
    required this.draft,
    required this.photo,
    required this.onChanged,
    required this.onPhoto,
    required this.onNext,
  });

  final AppSettings draft;
  final Uint8List? photo;
  final ValueChanged<AppSettings> onChanged;
  final ValueChanged<Uint8List?> onPhoto;
  final VoidCallback onNext;

  @override
  State<_YouPage> createState() => _YouPageState();
}

class _YouPageState extends State<_YouPage> {
  late final _name = TextEditingController(text: widget.draft.displayName);
  late final _tid = TextEditingController(text: widget.draft.trackerId);
  late final _device = TextEditingController(text: widget.draft.deviceName);
  late bool _tidTouched =
      widget.draft.trackerId.isNotEmpty &&
      widget.draft.trackerId !=
          trackerIdFromDisplayName(widget.draft.displayName);
  late bool _deviceTouched =
      widget.draft.deviceName.isNotEmpty &&
      widget.draft.deviceName !=
          deviceNameFromDisplayName(widget.draft.displayName);

  @override
  void dispose() {
    _name.dispose();
    _tid.dispose();
    _device.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.draft.copyWith(
        displayName: _name.text.trim(),
        trackerId: _tid.text.trim().toUpperCase(),
        deviceName: sanitizeTopicSegment(_device.text.trim()),
      ),
    );
  }

  void _onName(String v) {
    if (!_tidTouched) _tid.text = trackerIdFromDisplayName(v);
    if (!_deviceTouched) _device.text = deviceNameFromDisplayName(v);
    _emit();
    setState(() {});
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
    if (cropped != null) widget.onPhoto(cropped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ready =
        _name.text.trim().isNotEmpty &&
        sanitizeTopicSegment(_device.text).isNotEmpty &&
        _tid.text.trim().isNotEmpty;
    final initials = _tid.text.trim().isEmpty
        ? '?'
        : _tid.text.trim().toUpperCase();

    return _PageScaffold(
      icon: Icons.face_rounded,
      title: 'Who are you?',
      subtitle: 'This is how you\'ll appear to everyone else.',
      primary: FilledButton(
        onPressed: ready ? widget.onNext : null,
        child: const Text('Continue'),
      ),
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _photoSheet(context),
            child: Stack(
              children: [
                Avatar(
                  colorKey:
                      '${widget.draft.baseTopic}/${widget.draft.username}/${_device.text}',
                  initials: initials,
                  face: widget.photo,
                  size: 112,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 3),
                    ),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      size: 18,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => _photoSheet(context),
            child: Text(widget.photo == null ? 'Add a photo' : 'Change photo'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Fred Durk',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
          onChanged: _onName,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tid,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Initials',
                  helperText: 'On the map',
                  counterText: '',
                ),
                onChanged: (_) {
                  _tidTouched = true;
                  _emit();
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _device,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Device name',
                  helperText: 'Letters & numbers only',
                ),
                onChanged: (_) {
                  _deviceTouched = true;
                  _emit();
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Your phone will appear as ${widget.draft.baseTopic}/${widget.draft.username}/'
          '${sanitizeTopicSegment(_device.text).isEmpty ? '…' : sanitizeTopicSegment(_device.text)}. '
          'Use a different name from everyone else in the group.',
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  void _photoSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from library'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            if (widget.photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onPhoto(null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- history --

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({
    required this.draft,
    required this.onChanged,
    required this.onNext,
  });

  final AppSettings draft;
  final ValueChanged<AppSettings> onChanged;
  final VoidCallback onNext;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  late final _url = TextEditingController(text: widget.draft.recorderUrl);
  bool _testing = false;
  String? _error;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _error = null;
      _ok = false;
    });
    final err = await context.read<AppState>().testRecorder(
      widget.draft.copyWith(recorderUrl: _url.text.trim()),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _error = err;
      _ok = err == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = _url.text.trim().isNotEmpty;
    return _PageScaffold(
      icon: Icons.timeline_rounded,
      title: 'See where people have been',
      subtitle:
          'If your server runs the OwnTracks Recorder, add its web address to '
          'see each person\'s last few days. You can do this later.',
      primary: FilledButton(
        onPressed: widget.onNext,
        child: Text(hasUrl ? 'Continue' : 'Skip for now'),
      ),
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Recorder address',
            hintText: 'e.g. https://tracking.example.com/owntracks',
            prefixIcon: Icon(Icons.link_rounded),
          ),
          onChanged: (v) {
            widget.onChanged(widget.draft.copyWith(recorderUrl: v.trim()));
            setState(() {
              _ok = false;
              _error = null;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Uses the same username and password as your server. You can set a '
          'separate one in Settings.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (hasUrl)
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.wifi_tethering_rounded),
            label: Text(_testing ? 'Checking…' : 'Check address'),
          ),
        if (_ok || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(
                  _ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: _ok ? FlockColors.online : FlockColors.danger,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(_ok ? 'History server found.' : _error!)),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- location --

class _LocationPage extends StatefulWidget {
  const _LocationPage({required this.onFinish, required this.finishing});
  final Future<void> Function() onFinish;
  final bool finishing;

  @override
  State<_LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<_LocationPage>
    with WidgetsBindingObserver {
  LocationAccess? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final a = await context.read<AppState>().location.access();
    if (mounted) setState(() => _access = a);
  }

  Future<void> _request() async {
    final loc = context.read<AppState>().location;
    final before = _access;
    var a = await loc.request();
    // Some phones won't show the "all the time" prompt; send them to settings.
    if (before == LocationAccess.whileUsing && a == LocationAccess.whileUsing) {
      await loc.openSettings();
    }
    a = await loc.access();
    if (mounted) setState(() => _access = a);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<AppState>().location;
    final a = _access;

    final (
      String title,
      String body,
      String? action,
      VoidCallback? onAction,
    ) = switch (a) {
      null => ('Share your location', '', null, null),
      LocationAccess.notAsked => (
        'Share your location',
        'Your friends see you on the map only when you allow location access.',
        'Allow location',
        _request,
      ),
      LocationAccess.whileUsing => (
        'One more thing',
        'Choose "Allow all the time" so your friends can still see you when the '
            'app is closed. Without it, your dot only moves while the app is open.',
        'Allow all the time',
        _request,
      ),
      LocationAccess.always => (
        'You\'re all set',
        'Your location will be shared in the background. You can pause sharing '
            'any time from Settings.',
        null,
        null,
      ),
      LocationAccess.denied => (
        'Location is blocked',
        'Location access was turned off for this app. Open Settings and allow '
            'location "All the time".',
        'Open Settings',
        () => loc.openSettings(),
      ),
      LocationAccess.servicesOff => (
        'Location is off',
        'Location services are turned off on this phone.',
        'Turn on location',
        () => loc.openLocationSettings(),
      ),
    };

    final done = a == LocationAccess.always;
    return _PageScaffold(
      icon: done ? Icons.check_circle_rounded : Icons.location_on_rounded,
      title: title,
      subtitle: body,
      primary: done || action == null
          ? FilledButton(
              onPressed: widget.finishing ? null : widget.onFinish,
              child: widget.finishing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Start'),
            )
          : FilledButton(onPressed: onAction, child: Text(action)),
      secondary: done || action == null
          ? null
          : TextButton(
              onPressed: widget.finishing ? null : widget.onFinish,
              child: const Text('Not now'),
            ),
      children: [
        _PermissionStep(
          n: 1,
          text: 'Allow location while using the app',
          done: a == LocationAccess.whileUsing || a == LocationAccess.always,
        ),
        const SizedBox(height: 10),
        _PermissionStep(
          n: 2,
          text: 'Allow all the time, for background updates',
          done: a == LocationAccess.always,
        ),
      ],
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.n,
    required this.text,
    required this.done,
  });
  final int n;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: done
                  ? FlockColors.online
                  : cs.primary.withOpacity(0.12),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    )
                  : Text(
                      '$n',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
          ],
        ),
      ),
    );
  }
}
