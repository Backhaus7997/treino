import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/presentation/widgets/profile_header.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildHeader({GoRouter? router}) {
  final effectiveRouter = router ??
      GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(
              body: ProfileHeader(),
            ),
          ),
        ],
      );

  return ProviderScope(
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: effectiveRouter,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-494
// SCENARIO-495: REMOVED 2026-05-28 — Gear icon navigation to /profile/settings
// was removed as part of the PR#4 pivot. The ProfileHeader no longer contains
// a gear icon or any settings navigation.
// ---------------------------------------------------------------------------

void main() {
  group('ProfileHeader', () {
    // SCENARIO-494: renders "TU CUENTA" and "PERFIL" texts (gear icon absent)
    testWidgets(
        'SCENARIO-494: renders "TU CUENTA" and "PERFIL" texts; no gear icon',
        (tester) async {
      await tester.pumpWidget(_buildHeader());
      await tester.pumpAndSettle();

      expect(find.text('TU CUENTA'), findsOneWidget);
      expect(find.text('PERFIL'), findsOneWidget);
      // SCENARIO-495 was removed — gear icon is now absent.
      expect(find.byKey(const Key('profile_header_gear')), findsNothing);
    });

    // SCENARIO-495: REMOVED 2026-05-28 — gear icon navigation removed.
    // testWidgets('SCENARIO-495: tapping gear icon navigates to /profile/settings', ...)
    // ← REMOVED. Settings surface deferred to a future SDD.
  });
}
