import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// The dashboard header avatar was a bare decoration — no tap handler at all
// (unlike the bell right next to it, which was already wired to the
// pending-requests modal and only looks inert at badgeCount == 0). It now
// shortcuts to the trainer's own profile.

const _kTrainer = 'trainer-1';

UserProfile _trainerProfile() => UserProfile(
      uid: _kTrainer,
      email: 'mateo@test.com',
      displayName: 'Mateo Presset',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<GoRouter> _pumpDashboard(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: TrainerDashboardTab()),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PERFIL-STUB')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userProfileProvider
            .overrideWith((ref) => Stream.value(_trainerProfile())),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream<UserPublicProfile?>.value(null),
        ),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream.value(const <TrainerLink>[]),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

void main() {
  group('trainer dashboard header avatar', () {
    testWidgets('tapping the avatar navigates to the profile tab',
        (tester) async {
      final router = await _pumpDashboard(tester);

      // The initials come from the trainer's own display name.
      expect(find.text('MP'), findsOneWidget);

      await tester.tap(find.text('MP'));
      await tester.pumpAndSettle();

      expect(find.text('PERFIL-STUB'), findsOneWidget);
      // `go`, not `push` — PERFIL is a shell tab, so this is a tab switch and
      // must REPLACE the location rather than stack on top of /home.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/profile'),
      );
    });

    testWidgets('the avatar exposes button semantics with an action label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester);

      expect(find.bySemanticsLabel('Ver tu perfil'), findsOneWidget);
      handle.dispose();
    });

    // Both header controls need `container: true` on their Semantics or the
    // annotation merges into the enclosing node — the whole header was being
    // announced as ONE blob ("MARTES 28 JULIO HOLA, MATEO 0 solicitudes
    // pendientes Ver tu perfil"). The bell had this defect before the avatar
    // was ever wired.
    testWidgets('bell and avatar are SEPARATE nodes, not one merged header',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester);

      expect(find.bySemanticsLabel('0 solicitudes pendientes'), findsOneWidget);
      expect(find.bySemanticsLabel('Ver tu perfil'), findsOneWidget);
      // The greeting must NOT carry either control's label.
      expect(
        find.bySemanticsLabel(RegExp(r'HOLA, MATEO.*(solicitudes|perfil)')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('the avatar meets the 44pt minimum touch target',
        (tester) async {
      await _pumpDashboard(tester);

      // The painted circle is only 36px; measure the GESTURE DETECTOR — the
      // actual tap target — not the avatar, and not the inner ConstrainedBox
      // the 36px Container mounts of its own.
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(ConstrainedBox),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
    });
  });
}
