// ignore_for_file: deprecated_member_use
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../services/location_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'groups_screen.dart';
import 'photo_crop_screen.dart';

/// Welcome → You (makes your account) → Group → Location → done.
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
  bool _finishing = false;

  static const _count = 4;

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

  /// Makes your account the first time; after that just saves name changes.
  Future<String?> _saveYou() async {
    final app = context.read<AppState>();
    if (!app.settings.hasAccount) {
      final err = await app.createAccount(_draft.displayName);
      if (err != null) return err;
    }
    await app.updateSettings(
      app.settings.copyWith(
        displayName: _draft.displayName,
        trackerId: _draft.trackerId,
      ),
    );
    setState(() => _draft = app.settings);
    return null;
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
                  _YouPage(
                    draft: _draft,
                    photo: _photo,
                    onChanged: (s) => setState(() => _draft = s),
                    onPhoto: (b) => setState(() => _photo = b),
                    onSave: _saveYou,
                    onNext: _next,
                  ),
                  _GroupPage(onNext: _next),
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

// --------------------------------------------------------------------- you --

class _YouPage extends StatefulWidget {
  const _YouPage({
    required this.draft,
    required this.photo,
    required this.onChanged,
    required this.onPhoto,
    required this.onSave,
    required this.onNext,
  });

  final AppSettings draft;
  final Uint8List? photo;
  final ValueChanged<AppSettings> onChanged;
  final ValueChanged<Uint8List?> onPhoto;

  /// Creates the account (or saves a changed name). Returns an error message.
  final Future<String?> Function() onSave;
  final VoidCallback onNext;

  @override
  State<_YouPage> createState() => _YouPageState();
}

class _YouPageState extends State<_YouPage> {
  late final _name = TextEditingController(text: widget.draft.displayName);
  late final _tid = TextEditingController(text: widget.draft.trackerId);
  late bool _tidTouched =
      widget.draft.trackerId.isNotEmpty &&
      widget.draft.trackerId !=
          trackerIdFromDisplayName(widget.draft.displayName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _tid.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.draft.copyWith(
        displayName: _name.text.trim(),
        trackerId: _tid.text.trim().toUpperCase(),
      ),
    );
  }

  void _onName(String v) {
    if (!_tidTouched) _tid.text = trackerIdFromDisplayName(v);
    _emit();
    setState(() => _error = null);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = err;
    });
    if (err == null) widget.onNext();
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
    final ready =
        _name.text.trim().isNotEmpty && _tid.text.trim().isNotEmpty && !_saving;
    final hasAccount = context.watch<AppState>().settings.hasAccount;
    final initials = _tid.text.trim().isEmpty
        ? '?'
        : _tid.text.trim().toUpperCase();

    return _PageScaffold(
      icon: Icons.face_rounded,
      title: 'Who are you?',
      subtitle:
          'This is how you\'ll appear to everyone else. Use your real name '
          'so your group leader knows it\'s you.',
      primary: FilledButton(
        onPressed: ready ? _save : null,
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(hasAccount ? 'Continue' : 'Create my account'),
      ),
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _photoSheet(context),
            child: Stack(
              children: [
                Avatar(
                  colorKey: widget.draft.ownTopic,
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
        TextField(
          controller: _tid,
          maxLength: 2,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Initials',
            helperText: 'Shown on the map when there\'s no photo',
            counterText: '',
          ),
          onChanged: (_) {
            _tidTouched = true;
            _emit();
            setState(() {});
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.error_rounded, color: FlockColors.danger),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!)),
            ],
          ),
        ],
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

// ------------------------------------------------------------------- group --

class _GroupPage extends StatelessWidget {
  const _GroupPage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>().account;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final inSomething =
        a != null && (a.groups.isNotEmpty || a.pending.isNotEmpty);
    return _PageScaffold(
      icon: Icons.groups_rounded,
      title: 'Your group',
      subtitle:
          'You see the people in your groups, and they see you. Nobody else '
          'can. Start one and share its code, or enter a code someone sent you.',
      primary: FilledButton(
        onPressed: onNext,
        child: Text(inSomething ? 'Continue' : 'Skip for now'),
      ),
      children: [
        if (a != null) ...[
          for (final g in a.groups) GroupCard(group: g),
          for (final p in a.pending) PendingCard(pending: p),
        ],
        if (!inSomething) ...[
          Text('Got a code?', style: t.titleMedium),
          const SizedBox(height: 8),
          const JoinGroupForm(),
          const SizedBox(height: 28),
          Text('Or start a new group', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'You\'ll be its leader: you get a code to share and decide who '
            'gets in.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          const CreateGroupForm(),
        ],
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
