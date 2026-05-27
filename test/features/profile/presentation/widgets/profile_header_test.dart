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
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, __) =>
                    const Scaffold(body: Text('SETTINGS_SCREEN')),
              ),
            ],
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
// Tests — SCENARIO-494, SCENARIO-495
// ---------------------------------------------------------------------------

void main() {
  group('ProfileHeader', () {
    // SCENARIO-494: renders "TU CUENTA" and "PERFIL" texts
    testWidgets('SCENARIO-494: renders "TU CUENTA" and "PERFIL" texts',
        (tester) async {
      await tester.pumpWidget(_buildHeader());
      await tester.pumpAndSettle();

      expect(find.text('TU CUENTA'), findsOneWidget);
      expect(find.text('PERFIL'), findsOneWidget);
    });

    // SCENARIO-495: tapping the gear icon navigates to /profile/settings
    testWidgets(
        'SCENARIO-495: tapping gear icon navigates to /profile/settings',
        (tester) async {
      await tester.pumpWidget(_buildHeader());
      await tester.pumpAndSettle();

      // Tap the GestureDetector wrapping the gear icon.
      // The gear is the only GestureDetector in ProfileHeader's trailing slot.
      await tester.tap(find.byKey(const Key('profile_header_gear')));
      await tester.pumpAndSettle();

      expect(find.text('SETTINGS_SCREEN'), findsOneWidget);
    });
  });
}
