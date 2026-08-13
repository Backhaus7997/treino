// Tests for ProfileRoutinesScreen — read-only mirror of the UNIFIED routines
// list (workout-area redesign slice 1, 2026-07-27): coach plans pinned on top
// with "DE TU COACH" chip, ACTIVA chip by activeRoutineId match (always), and
// the "Buscar PF" promo card while no coach plan exists.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_routines_screen.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

class _MockUserRepository extends Mock implements UserRepository {}

const _uid = 'test-uid';

Routine _assignedRoutine({required String id, required String name}) => Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-uid',
      assignedTo: _uid,
      visibility: RoutineVisibility.private,
    );

Routine _ownRoutine({required String id, required String name}) => Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      createdBy: _uid,
      visibility: RoutineVisibility.private,
    );

UserProfile _profile({String? activeRoutineId}) => UserProfile(
      uid: _uid,
      email: 'test@treino.app',
      displayName: 'Test',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

Widget _buildScreen({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/profile/routines',
    routes: [
      GoRoute(
        path: '/profile/routines',
        builder: (_, __) => const Scaffold(body: ProfileRoutinesScreen()),
      ),
      GoRoute(
        path: '/coach',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('COACH_DESTINATION'))),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  group('ProfileRoutinesScreen — unified list', () {
    final mockUser = MockUser();
    late _MockUserRepository userRepo;

    setUp(() {
      // unifiedRoutinesProvider's lazy adoption writes activeRoutineId when
      // the profile resolves without one — always absorb it with a mock.
      userRepo = _MockUserRepository();
      when(() => userRepo.update(any(), any())).thenAnswer((_) async {});
    });

    List<Override> baseOverrides({
      required List<Routine> assigned,
      required List<Routine> own,
      String? activeRoutineId,
    }) =>
        [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          assignedRoutinesProvider(_uid).overrideWith((_) async => assigned),
          userCreatedRoutinesProvider(_uid)
              .overrideWith((_) => Stream.value(own)),
          userProfileProvider.overrideWith(
            (_) => Stream.value(_profile(activeRoutineId: activeRoutineId)),
          ),
          userRepositoryProvider.overrideWithValue(userRepo),
        ];

    testWidgets(
        'coach plan pinned ABOVE own routines in a single list, with the '
        'DE TU COACH chip', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: [_assignedRoutine(id: 'a1', name: 'Plan Fuerza')],
          own: [_ownRoutine(id: 'o1', name: 'PPL')],
          activeRoutineId: 'a1',
        ),
      ));
      await tester.pumpAndSettle();

      // Old section headers are gone — one unified list.
      expect(find.text('RUTINAS ASIGNADAS POR TU PF'), findsNothing);
      expect(find.text('MIS RUTINAS PROPIAS'), findsNothing);

      expect(find.text('PLAN FUERZA'), findsOneWidget);
      expect(find.text('PPL'), findsOneWidget);
      final coachY = tester.getTopLeft(find.text('PLAN FUERZA')).dy;
      final ownY = tester.getTopLeft(find.text('PPL')).dy;
      expect(coachY, lessThan(ownY), reason: 'coach plan pinned on top');

      expect(find.byKey(const Key('profile_routines_coach_chip_a1')),
          findsOneWidget);
      expect(find.text('DE TU COACH'), findsOneWidget);
    });

    testWidgets(
        'no routines at all → empty card + BUSCAR PF promo render together',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(assigned: const [], own: const []),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('profile_routines_own_empty')), findsOneWidget);
      expect(find.byKey(const Key('profile_routines_assigned_empty')),
          findsOneWidget);
      expect(find.byKey(const Key('profile_routines_find_trainer_cta')),
          findsOneWidget);
      expect(find.text('BUSCAR PF'), findsOneWidget);
    });

    testWidgets('tap "BUSCAR PF" navigates to /coach (the trainers directory)',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(assigned: const [], own: const []),
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('profile_routines_find_trainer_cta')));
      await tester.pumpAndSettle();

      expect(find.text('COACH_DESTINATION'), findsOneWidget);
    });

    testWidgets(
        'with a coach plan present → the BUSCAR PF promo does NOT render',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: [
            _assignedRoutine(id: 'a1', name: 'Plan Hipertrofia'),
            _assignedRoutine(id: 'a2', name: 'Plan Fuerza'),
          ],
          own: const [],
          activeRoutineId: 'a1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PLAN HIPERTROFIA'), findsOneWidget);
      expect(find.text('PLAN FUERZA'), findsOneWidget);
      expect(find.byKey(const Key('profile_routines_assigned_empty')),
          findsNothing);
    });

    testWidgets(
        'own routines only → cards render + promo still visible below '
        '(discovery stays promoted while no coach)', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: const [],
          own: [
            _ownRoutine(id: 'o1', name: 'PPL'),
            _ownRoutine(id: 'o2', name: 'Full Body'),
          ],
          activeRoutineId: 'o1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PPL'), findsOneWidget);
      expect(find.text('FULL BODY'), findsOneWidget);
      expect(find.byKey(const Key('profile_routines_own_empty')), findsNothing);
      expect(find.byKey(const Key('profile_routines_assigned_empty')),
          findsOneWidget);
    });

    testWidgets(
        'ACTIVA chip renders on the matching card — even with a SINGLE '
        'routine (slice 1 contract: no >1 gate)', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: const [],
          own: [_ownRoutine(id: 'o1', name: 'PPL')],
          activeRoutineId: 'o1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_routines_active_chip')),
          findsOneWidget);
      expect(find.text('ACTIVA'), findsOneWidget);
    });

    testWidgets('ACTIVA chip can sit on the coach plan card', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: [_assignedRoutine(id: 'a1', name: 'Plan Fuerza')],
          own: [_ownRoutine(id: 'o1', name: 'PPL')],
          activeRoutineId: 'a1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_routines_active_chip')),
          findsOneWidget);
      // Both chips coexist on the pinned coach card.
      expect(find.byKey(const Key('profile_routines_coach_chip_a1')),
          findsOneWidget);
    });

    testWidgets(
        'ACTIVA chip is HIDDEN when activeRoutineId matches nothing '
        '(stale pointer)', (tester) async {
      await tester.pumpWidget(_buildScreen(
        overrides: baseOverrides(
          assigned: const [],
          own: [
            _ownRoutine(id: 'o1', name: 'PPL'),
            _ownRoutine(id: 'o2', name: 'Full Body'),
          ],
          activeRoutineId: 'archived-id',
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('profile_routines_active_chip')), findsNothing);
    });

    testWidgets('shows loader while the unified list is loading',
        (tester) async {
      // Use a Completer that never completes to hold loading state without
      // creating a pending timer (would fail test teardown).
      final completer = Completer<List<Routine>>();
      await tester.pumpWidget(_buildScreen(
        overrides: [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          assignedRoutinesProvider(_uid).overrideWith((_) => completer.future),
          userCreatedRoutinesProvider(_uid)
              .overrideWith((_) => Stream<List<Routine>>.value(const [])),
          userProfileProvider.overrideWith((_) => Stream.value(_profile())),
          userRepositoryProvider.overrideWithValue(userRepo),
        ],
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));

      // Resolve to avoid resource leak warnings.
      completer.complete([]);
    });
  });
}
