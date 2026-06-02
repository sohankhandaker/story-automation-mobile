import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/sera_tokens.dart';
import 'theme/sera_theme.dart';

// ── Brand constants — aliases of design-system tokens ─────────────────────────
// Kept so all existing kPrimary / kSurface references keep compiling.
const kPrimary      = SeraTokens.primary;
const kPrimaryDark  = SeraTokens.primaryDark;
const kPrimaryLight = SeraTokens.primaryLight;
const kSurface      = SeraTokens.surface;
const kDeepNavy     = SeraTokens.deepNavy;

// ── App root ───────────────────────────────────────────────────────────────────

class StoryApp extends ConsumerWidget {
  const StoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SERA',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: buildSeraTheme(),
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final showSplash = !_splashDone || auth.initializing;

    Widget child;
    String key;
    if (showSplash) {
      child = const SplashScreen();
      key = 'splash';
    } else if (auth.isAuthenticated) {
      child = const DashboardScreen();
      key = 'dashboard';
    } else {
      child = const LoginScreen();
      key = 'login';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(key), child: child),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
