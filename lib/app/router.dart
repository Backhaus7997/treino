import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/treino_bottom_bar.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/workout/workout_screen.dart';
import 'theme/app_background.dart';

const _kTabs = ['/workout', '/feed', '/home', '/coach', '/profile'];
const _authRoutes = {'/login', '/register', '/forgot-password'};

/// Pure redirect logic — extracted as a top-level function so it is unit-testable
/// without a widget tree (REQ-AUTH-022, REQ-AUTH-023, REQ-AUTH-024).
///
/// [read] is a `Ref.read`-equivalent that returns the current state of any
/// provider. In production this is `ref.read`; in tests it is
/// `container.read`.
String? authRedirect(
    T Function<T>(ProviderListenable<T> provider) read, String location) {
  final auth = read(authNotifierProvider);

  // REQ-AUTH-024: while loading, do not redirect.
  if (auth.isLoading || !auth.hasValue) return null;

  final user = auth.valueOrNull;
  final loggedIn = user != null;
  final isAuthRoute = _authRoutes.any(location.startsWith);

  // REQ-AUTH-023:
  if (!loggedIn && !isAuthRoute) return '/login';
  if (loggedIn && isAuthRoute) return '/home';
  return null;
}

GoRouter buildRouter({
  required Listenable refreshListenable,
  required T Function<T>(ProviderListenable<T>) read,
}) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    redirect: (ctx, state) => authRedirect(read, state.matchedLocation),
    routes: [
      // Auth routes — full screen, NO bottom bar
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _noAnim(const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, __) => _noAnim(const RegisterScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, __) => _noAnim(const ForgotPasswordScreen()),
      ),

      // ShellRoute with the existing 5 tabs
      ShellRoute(
        builder: (context, state, child) => _ShellScaffold(
          location: state.uri.toString(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/workout',
            pageBuilder: (_, __) => _noAnim(const WorkoutScreen()),
          ),
          GoRoute(
            path: '/feed',
            pageBuilder: (_, __) => _noAnim(const FeedScreen()),
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _noAnim(const HomeScreen()),
          ),
          GoRoute(
            path: '/coach',
            pageBuilder: (_, __) => _noAnim(const CoachScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => _noAnim(const ProfileScreen()),
          ),
        ],
      ),
    ],
  );
}

CustomTransitionPage<void> _noAnim(Widget child) => CustomTransitionPage(
      child: child,
      transitionsBuilder: (_, __, ___, child) => child,
    );

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  int get _currentIndex {
    final i = _kTabs.indexWhere((t) => location.startsWith(t));
    return i < 0 ? 2 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(child: SafeArea(child: child)),
      bottomNavigationBar: TreinoBottomBar(
        currentIndex: _currentIndex,
        onTap: (i) => context.go(_kTabs[i]),
      ),
    );
  }
}
