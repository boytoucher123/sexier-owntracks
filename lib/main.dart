// ignore_for_file: deprecated_member_use
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final app = AppState();
  await app.init();
  // Invite links (flock://host/join/CODE) open the app with the invite
  // filled in. This also delivers the link the app was launched with.
  AppLinks().uriLinkStream.listen(
    (uri) => app.offerInvite(uri.toString()),
    onError: (_) {},
  );
  runApp(FlockApp(state: app));
}

class FlockApp extends StatelessWidget {
  const FlockApp({
    super.key,
    required this.state,
    this.themeMode = ThemeMode.system,
  });
  final AppState state;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: Txt.flock,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final setup = context.select<AppState, bool>(
      (a) => a.settings.setupComplete,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: setup
          ? const HomeScreen(key: ValueKey('home'))
          : const OnboardingScreen(key: ValueKey('onboarding')),
    );
  }
}
