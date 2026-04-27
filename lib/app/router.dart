import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/treino_bottom_bar.dart';
import '../features/coach/coach_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/workout/workout_screen.dart';
import 'theme/app_background.dart';

const _kTabs = ['/workout', '/feed', '/home', '/coach', '/profile'];

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
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
