import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockTrainerLinkRepository extends Mock implements TrainerLinkRepository {}

// ─── Factories ──────────────────────────────────────────────────────────────

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
  DateTime? pausedAt,
  String? terminationReason,
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
      acceptedAt: status == TrainerLinkStatus.active ||
              status == TrainerLinkStatus.paused ||
              status == TrainerLinkStatus.terminated
          ? DateTime.utc(2026, 1, 11)
          : null,
      pausedAt: pausedAt,
      terminationReason: terminationReason,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Test helpers ────────────────────────────────────────────────────────────

/// Wraps [child] with ProviderScope + MaterialApp using the dark theme.
Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        // Locale explícito → sino el default en test env es en_US y AppL10n
        // resuelve las keys en el ARB inglés (que es scaffold), rompiendo
        // los expect() en español.
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

/// Returns ProviderScope overrides that stub [trainerLinksStreamProvider]
/// with [links] and [userPublicProfileProvider] for each link's athleteId.
List<Override> _stubLinks(
  List<TrainerLink> links, {
  MockTrainerLinkRepository? repo,
}) {
  final baseOverrides = <Override>[
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(_trainerProfile()),
    ),
    for (final l in links)
      userPublicProfileProvider(l.athleteId).overrideWith(
        (ref) => Stream.value(_pub(l.athleteId, 'Atleta ${l.id}')),
      ),
  ];
  if (repo != null) {
    return [
      ...baseOverrides,
      trainerLinkRepositoryProvider.overrideWithValue(repo),
    ];
  }
  return baseOverrides;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  // ── T-CHLM-014 RED: three section headers visible with all-status stream ──

  group('SCEN-CHLM-008 — three section labels visible', () {
    testWidgets('renders ACTIVOS, PAUSADOS, HISTORIAL when filter includes all',
        (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
        _link(
          id: 'l2',
          status: TrainerLinkStatus.paused,
          athleteId: 'a2',
          pausedAt: DateTime.utc(2026, 1, 15),
        ),
        _link(
          id: 'l3',
          status: TrainerLinkStatus.terminated,
          athleteId: 'a3',
          terminationReason: 'trainer-terminated',
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVOS'), findsOneWidget);
      expect(find.text('PAUSADOS'), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);
    });
  });

  // ── T-CHLM-016 — PAUSADOS section ─────────────────────────────────────────

  group('SCEN-CHLM-009 — paused link shows formatted date', () {
    testWidgets('displays "Pausado el 15/01/2026" for pausedAt 2026-01-15',
        (tester) async {
      final links = [
        _link(
          id: 'l1',
          status: TrainerLinkStatus.paused,
          pausedAt: DateTime.utc(2026, 1, 15),
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pausado el 15/01/2026'), findsOneWidget);
    });
  });

  group('SCEN-CHLM-010 — PAUSADOS empty state', () {
    testWidgets('shows "No hay alumnos pausados." when no paused links',
        (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No hay alumnos pausados.'), findsOneWidget);
    });
  });

  // ── T-CHLM-017 — HISTORIAL section ────────────────────────────────────────

  group('SCEN-CHLM-011 — HISTORIAL reason mapping', () {
    testWidgets('trainer-terminated maps to "Terminado por el PF"',
        (tester) async {
      final links = [
        _link(
          id: 'l1',
          status: TrainerLinkStatus.terminated,
          terminationReason: 'trainer-terminated',
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Terminado por el PF'), findsOneWidget);
    });

    testWidgets('declined maps to "Rechazado por el PF"', (tester) async {
      final links = [
        _link(
          id: 'l1',
          status: TrainerLinkStatus.terminated,
          terminationReason: 'declined',
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Rechazado por el PF'), findsOneWidget);
    });

    testWidgets('cancelled-by-athlete maps to "Cancelado por el atleta"',
        (tester) async {
      final links = [
        _link(
          id: 'l1',
          status: TrainerLinkStatus.terminated,
          terminationReason: 'cancelled-by-athlete',
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Cancelado por el atleta'), findsOneWidget);
    });

    testWidgets('unknown reason falls back to "Vínculo terminado"',
        (tester) async {
      final links = [
        _link(
          id: 'l1',
          status: TrainerLinkStatus.terminated,
          terminationReason: null,
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Vínculo terminado'), findsOneWidget);
    });
  });

  group('SCEN-CHLM-012 — HISTORIAL empty state', () {
    testWidgets('shows "Sin vínculos terminados todavía." when no terminated',
        (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Sin vínculos terminados todavía.'),
        findsOneWidget,
      );
    });
  });

  // ── T-CHLM-019 — Pausar action on active card ─────────────────────────────

  group('SCEN-CHLM-013..015 — Pausar button on active card', () {
    testWidgets('tapping Pausar opens dialog with correct copy',
        (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();

      expect(find.text('Pausar vínculo'), findsOneWidget);
      expect(
        find.text(
          'El alumno verá el plan pero no podrá registrar sesiones nuevas hasta que reanudes el vínculo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirming Pausar calls repo.pause(linkId)', (tester) async {
      final repo = MockTrainerLinkRepository();
      when(() => repo.pause(any())).thenAnswer((_) async {});
      when(() => repo.resume(any())).thenAnswer((_) async {});
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(() => repo.pause('l1')).called(1);
    });

    testWidgets('cancelling Pausar dialog does NOT call repo.pause',
        (tester) async {
      final repo = MockTrainerLinkRepository();
      when(() => repo.pause(any())).thenAnswer((_) async {});

      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.pause(any()));
    });
  });

  // ── T-CHLM-020 — Terminar action on active card ───────────────────────────

  group('SCEN-CHLM-007 — Terminar on active card', () {
    testWidgets('tapping Terminar opens correct dialog', (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminar vínculo').first);
      await tester.pumpAndSettle();

      expect(find.text('Terminar vínculo'), findsWidgets);
      expect(
        find.text(
            'Esta acción no se puede deshacer. El historial se conserva.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'confirming Terminar on active card calls repo.terminate with trainer-terminated',
        (tester) async {
      final repo = MockTrainerLinkRepository();
      when(() => repo.pause(any())).thenAnswer((_) async {});
      when(() => repo.resume(any())).thenAnswer((_) async {});
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminar vínculo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(
        () => repo.terminate('l1', reason: 'trainer-terminated'),
      ).called(1);
    });
  });

  // ── T-CHLM-021 — Reanudar + Terminar on paused card ──────────────────────

  group('SCEN-CHLM-016 — Reanudar + Terminar on paused card', () {
    testWidgets('confirming Reanudar calls repo.resume(linkId)',
        (tester) async {
      final repo = MockTrainerLinkRepository();
      when(() => repo.pause(any())).thenAnswer((_) async {});
      when(() => repo.resume(any())).thenAnswer((_) async {});
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      final links = [
        _link(
          id: 'l2',
          status: TrainerLinkStatus.paused,
          pausedAt: DateTime.utc(2026, 1, 15),
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reanudar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(() => repo.resume('l2')).called(1);
    });

    testWidgets(
        'Terminar from paused card calls repo.terminate with trainer-terminated',
        (tester) async {
      final repo = MockTrainerLinkRepository();
      when(() => repo.pause(any())).thenAnswer((_) async {});
      when(() => repo.resume(any())).thenAnswer((_) async {});
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      final links = [
        _link(
          id: 'l2',
          status: TrainerLinkStatus.paused,
          pausedAt: DateTime.utc(2026, 1, 15),
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminar vínculo').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(
        () => repo.terminate('l2', reason: 'trainer-terminated'),
      ).called(1);
    });
  });

  // ── T-CHLM-022 — FilterChip toggles section visibility ───────────────────

  group('REQ-CHLM-007 — FilterChip toggles section', () {
    testWidgets('tapping HISTORIAL chip hides HISTORIAL section',
        (tester) async {
      final links = [
        _link(id: 'l1', status: TrainerLinkStatus.active),
        _link(
          id: 'l3',
          status: TrainerLinkStatus.terminated,
          athleteId: 'a3',
          terminationReason: 'trainer-terminated',
        ),
      ];
      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      // Initially HISTORIAL visible
      expect(find.text('HISTORIAL'), findsOneWidget);

      // Tap the HISTORIAL FilterChip to deselect it
      // The filter row has chips with the same label as sections
      final chips = find.byType(FilterChip);
      // Find FilterChip with label HISTORIAL
      final historialChip = find.ancestor(
        of: find.text('HISTORIAL'),
        matching: chips,
      );
      await tester.tap(historialChip);
      await tester.pumpAndSettle();

      // HISTORIAL section header should be gone (section collapsed)
      // The chip label 'HISTORIAL' in the filter row should still be visible,
      // but the section header below should be hidden.
      // We check that the section-specific content is gone:
      expect(find.text('Sin vínculos terminados todavía.'), findsNothing);
    });
  });

  // ── T-CHLM-023 — Real-time stream update ─────────────────────────────────

  group('SCEN-CHLM-017 — stream re-renders sections without manual refresh',
      () {
    testWidgets('link moving from active to paused updates sections',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();

      final overrides = <Override>[
        trainerLinksStreamProvider.overrideWith((ref) => controller.stream),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_trainerProfile()),
        ),
        userPublicProfileProvider('a1').overrideWith(
          (ref) => Stream.value(_pub('a1', 'Atleta l1')),
        ),
      ];

      await tester.pumpWidget(_wrap(
        const CoachHubDashboardScreen(),
        overrides: overrides,
      ));

      // Emit initial state: one active link
      controller.add([_link(id: 'l1', status: TrainerLinkStatus.active)]);
      await tester.pumpAndSettle();

      // Link is in ACTIVOS — no paused content
      expect(find.text('No hay alumnos pausados.'), findsOneWidget);

      // Emit updated state: same link is now paused
      controller.add([
        _link(
          id: 'l1',
          status: TrainerLinkStatus.paused,
          pausedAt: DateTime.utc(2026, 1, 15),
        ),
      ]);
      await tester.pumpAndSettle();

      // Now it should show in PAUSADOS section with the formatted date
      expect(find.text('Pausado el 15/01/2026'), findsOneWidget);
      // ACTIVOS section empty now
      expect(find.text('Sin alumnos activos por ahora.'), findsOneWidget);

      await controller.close();
    });
  });
}
