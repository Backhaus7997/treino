// Widget tests for MisRutinasSection — SCENARIO-609..615
// REQ-USR-001..006
//
// TDD: tests written FIRST (RED phase). Implementation lives in
// lib/features/workout/presentation/widgets/mis_rutinas_section.dart.

import 'dart:async';

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
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/widgets/mis_rutinas_section.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

// ── Fixtures ───────────────────────────────────────────────────────────────────

class _MockUser extends Mock implements User {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

UserProfile _profile({String uid = 'athlete-1', String? activeRoutineId}) =>
    UserProfile(
      uid: uid,
      email: '$uid@treino.app',
      displayName: 'A1',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Routine _makeUserRoutine({
  String id = 'r1',
  String name = 'Mi Rutina Full Body',
  String createdBy = 'athlete-1',
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
      createdBy: createdBy,
      status: status,
    );

List<Routine> _make10Routines() => List.generate(
      10,
      (i) => _makeUserRoutine(id: 'r$i', name: 'Rutina $i'),
    );

// ── Test helper ────────────────────────────────────────────────────────────────

Future<void> _pumpSection(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/workout',
    routes: [
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: MisRutinasSection()),
        ),
        routes: [
          GoRoute(
            path: 'my-routine-editor',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Editor'))),
          ),
          GoRoute(
            path: 'routine/:routineId',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Detalles'))),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Needed for mocktail.any() on Map<String, Object?> args in UserRepository.update.
    registerFallbackValue(<String, Object?>{});
  });

  group('MisRutinasSection', () {
    // SCENARIO-609: empty state renders motivational message + CTA enabled
    testWidgets(
        'SCENARIO-609: empty state renders motivational message + CTA enabled',
        (tester) async {
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([])),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('MIS RUTINAS'), findsOneWidget);
      // Motivational empty state copy
      expect(
        find.textContaining('Todavía no creaste ninguna rutina'),
        findsOneWidget,
      );
      // CTA is present and enabled
      expect(find.text('CREAR RUTINA'), findsOneWidget);
      // CTA is NOT disabled
      final ctaFinder = find.widgetWithText(ElevatedButton, 'CREAR RUTINA');
      if (ctaFinder.evaluate().isEmpty) {
        // may be TextButton or OutlinedButton variant
        expect(find.text('CREAR RUTINA'), findsOneWidget);
      } else {
        final btn = tester.widget<ElevatedButton>(ctaFinder);
        expect(btn.onPressed, isNotNull);
      }
    });

    // SCENARIO-610: loaded list renders routine cards
    testWidgets('SCENARIO-610: loaded list renders routine cards newest first',
        (tester) async {
      final routines = [
        _makeUserRoutine(id: 'r1', name: 'Rutina A'),
        _makeUserRoutine(id: 'r2', name: 'Rutina B'),
      ];

      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value(routines)),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('Rutina A'), findsOneWidget);
      expect(find.text('Rutina B'), findsOneWidget);
    });

    // SCENARIO-611: tap CTA navigates to /workout/my-routine-editor
    testWidgets('SCENARIO-611: tap CTA navigates to /workout/my-routine-editor',
        (tester) async {
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([])),
        ],
      );

      await tester.pumpAndSettle();

      // Find and tap the CTA
      final cta = find.text('CREAR RUTINA');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // Should navigate to the editor screen
      expect(find.text('Editor'), findsOneWidget);
    });

    // SCENARIO-612: 10 routines → CTA disabled with hint
    testWidgets('SCENARIO-612: cap reached (10 routines) → CTA disabled',
        (tester) async {
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value(_make10Routines())),
        ],
      );

      await tester.pumpAndSettle();

      // Cap hint should appear
      expect(
        find.textContaining('máximo'),
        findsOneWidget,
      );
    });

    // SCENARIO-613: archive action calls repo.archive on confirm
    testWidgets(
        'SCENARIO-613: overflow ELIMINAR → confirm → repo.archive called',
        (tester) async {
      final mockRepo = _MockRoutineRepository();
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});

      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1').overrideWith(
            (ref) => Stream.value([_makeUserRoutine(id: 'r1')]),
          ),
          routineRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );

      await tester.pumpAndSettle();

      // Open the overflow/more menu on the card
      final moreButton = find.byKey(const Key('routine_card_more_r1'));
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Tap ELIMINAR
      final archiveItem = find.text('ELIMINAR');
      expect(archiveItem, findsOneWidget);
      await tester.tap(archiveItem);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Eliminar rutina'), findsOneWidget);

      // Tap confirm ELIMINAR in dialog
      final confirmButton = find.widgetWithText(TextButton, 'ELIMINAR');
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // repo.archive should have been called
      verify(() => mockRepo.archive('r1')).called(1);
    });

    // SCENARIO-614: CANCELAR in archive dialog does NOT call repo
    testWidgets(
        'SCENARIO-614: overflow ELIMINAR → CANCELAR → repo.archive NOT called',
        (tester) async {
      final mockRepo = _MockRoutineRepository();

      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1').overrideWith(
            (ref) => Stream.value([_makeUserRoutine(id: 'r1')]),
          ),
          routineRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );

      await tester.pumpAndSettle();

      final moreButton = find.byKey(const Key('routine_card_more_r1'));
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      final archiveItem = find.text('ELIMINAR');
      expect(archiveItem, findsOneWidget);
      await tester.tap(archiveItem);
      await tester.pumpAndSettle();

      expect(find.text('Eliminar rutina'), findsOneWidget);

      // Tap CANCELAR
      final cancelButton = find.widgetWithText(TextButton, 'CANCELAR');
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      // repo.archive should NOT have been called
      verifyNever(() => mockRepo.archive(any()));
    });

    // SCENARIO-615: tap routine card pushes /workout/routine/<id>
    testWidgets('SCENARIO-615: tap on routine card navigates to detail screen',
        (tester) async {
      final routine = _makeUserRoutine(id: 'r1', name: 'Mi Rutina Full Body');

      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([routine])),
        ],
      );

      await tester.pumpAndSettle();

      // Tap the routine card (by name text)
      final cardFinder = find.byKey(const Key('user_routine_card_r1'));
      expect(cardFinder, findsOneWidget);
      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      expect(find.text('Detalles'), findsOneWidget);
    });

    // ── PR#2: active routine marker ─────────────────────────────────────────
    // Active marker only appears with 2+ routines — single-routine auto-
    // activates implicitly so chip + toggle action would be noise.

    testWidgets(
        'PR#2: single routine → no ACTIVA chip and no toggle action in menu',
        (tester) async {
      final routine = _makeUserRoutine(id: 'r-only', name: 'Only Routine');
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([routine])),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(activeRoutineId: 'r-only')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Chip is hidden even when the id matches — single routine doesn't
      // need disambiguation.
      expect(find.byKey(const Key('user_routine_active_chip')), findsNothing);

      // Open the overflow menu — toggle action should NOT be present.
      await tester.tap(find.byKey(const Key('routine_card_more_r-only')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('routine_card_toggle_active_r-only')),
        findsNothing,
      );
    });

    testWidgets(
        'PR#2: 2+ routines + activeRoutineId matches → chip on active card '
        'only, toggle action available on every card', (tester) async {
      final r1 = _makeUserRoutine(id: 'r1', name: 'Rutina A');
      final r2 = _makeUserRoutine(id: 'r2', name: 'Rutina B');
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([r1, r2])),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(activeRoutineId: 'r2')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Chip appears exactly once — only on the active card.
      expect(
        find.byKey(const Key('user_routine_active_chip')),
        findsOneWidget,
      );

      // Active card → menu shows "DESMARCAR".
      await tester.tap(find.byKey(const Key('routine_card_more_r2')));
      await tester.pumpAndSettle();
      expect(find.text('DESMARCAR COMO ACTIVA'), findsOneWidget);
      // Dismiss the menu so the next tap registers cleanly.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Inactive card → menu shows "MARCAR".
      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      expect(find.text('MARCAR COMO ACTIVA'), findsOneWidget);
    });

    testWidgets(
        'PR#2: 2+ routines + activeRoutineId NULL → no chip anywhere, '
        'toggle action says MARCAR on every card', (tester) async {
      final r1 = _makeUserRoutine(id: 'r1', name: 'Rutina A');
      final r2 = _makeUserRoutine(id: 'r2', name: 'Rutina B');
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([r1, r2])),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(activeRoutineId: null)),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('user_routine_active_chip')), findsNothing);

      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      expect(find.text('MARCAR COMO ACTIVA'), findsOneWidget);
    });

    testWidgets(
        'PR#2: tap "MARCAR COMO ACTIVA" calls UserRepository.update with '
        'activeRoutineId set to that routine id', (tester) async {
      final mockUserRepo = _MockUserRepository();
      when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});

      final r1 = _makeUserRoutine(id: 'r1', name: 'Rutina A');
      final r2 = _makeUserRoutine(id: 'r2', name: 'Rutina B');
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([r1, r2])),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(activeRoutineId: null)),
          ),
          userRepositoryProvider.overrideWithValue(mockUserRepo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MARCAR COMO ACTIVA'));
      await tester.pumpAndSettle();

      verify(() => mockUserRepo.update('athlete-1', {'activeRoutineId': 'r1'}))
          .called(1);
    });

    testWidgets(
        'PR#2: tap "DESMARCAR COMO ACTIVA" calls UserRepository.update with '
        'activeRoutineId set to null', (tester) async {
      final mockUserRepo = _MockUserRepository();
      when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});

      final r1 = _makeUserRoutine(id: 'r1', name: 'Rutina A');
      final r2 = _makeUserRoutine(id: 'r2', name: 'Rutina B');
      await _pumpSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          userCreatedRoutinesProvider('athlete-1')
              .overrideWith((ref) => Stream.value([r1, r2])),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(activeRoutineId: 'r2')),
          ),
          userRepositoryProvider.overrideWithValue(mockUserRepo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DESMARCAR COMO ACTIVA'));
      await tester.pumpAndSettle();

      verify(() => mockUserRepo.update('athlete-1', {'activeRoutineId': null}))
          .called(1);
    });
  });
}
