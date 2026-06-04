import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/notes_screen.dart' show notesProvider;
import 'screens/projects_screen.dart' show projectsProvider, projectNotesProvider;
import 'screens/customers_screen.dart' show customersProvider;
import 'screens/customer_detail_screen.dart' show customerProjectsProvider;
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
  AppLinks? _appLinks;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _splashDone = true);
    });
    if (kIsWeb) {
      _handleWebAuthToken();
    } else {
      _initDeepLinks();
    }
  }

  // Web: extract ?auth_token= from the current URL after GitHub redirect
  void _handleWebAuthToken() {
    final uri = Uri.base;
    final token = uri.queryParameters['auth_token'];
    if (token != null && token.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(authProvider.notifier).loginWithToken(token);
      });
    }
  }

  // Mobile: listen for sera://auth?token= deep link
  void _initDeepLinks() {
    _appLinks = AppLinks();
    _appLinks!.uriLinkStream.listen((uri) async {
      if (uri.scheme == 'sera' && uri.host == 'auth') {
        final token = uri.queryParameters['token'];
        if (token != null && token.isNotEmpty && mounted) {
          await ref.read(authProvider.notifier).loginWithToken(token);
        }
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Invalidates all data providers when a different user logs in so the new
  /// user never sees another user's cached data.
  void _invalidateDataProviders() {
    ref.invalidate(notesProvider);
    ref.invalidate(projectsProvider);
    ref.invalidate(projectNotesProvider);
    ref.invalidate(customersProvider);
    ref.invalidate(customerProjectsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // When a *different* user logs in, clear all cached data immediately.
    ref.listen<AuthState>(authProvider, (previous, next) {
      final prevId = previous?.user?.id;
      final nextId = next.user?.id;
      if (nextId != null && prevId != null && prevId != nextId) {
        _invalidateDataProviders();
      }
    });
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
