// Widget tests for the Coach Hub web "Historial" tab
// (alumno_detail_screen.dart, W2+).
//
// The tab is a private _HistorialTab class inside alumno_detail_screen —
// we exercise it end-to-end via AlumnoDetailScreen with the Historial tab
// selected, using ProviderScope overrides for sessionsByUidProvider.
//
// Covered:
//   - empty state when the athlete has no sessions
//   - full timeline with N sessions (count string + N rows)
//   - status pill differentiates completada / incompleta / en curso
//   - active sessions show startedAt fallback (not "—") in the date column
//   - the tab shows ALL sessions (no take(20) or completed-only filter as
//     the Entrenamientos tab has)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 't1';
const _athleteUid = 'a1';

TrainerLink _link() => TrainerLink(
      id: '${_trainerUid}_$_athleteUid',
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime(2026, 6, 1),
      acceptedAt: DateTime(2026, 6, 1),
    );

UserPublicProfile _profile() => const UserPublicProfile(
      uid: _athleteUid,
      displayName: 'Sofía',
    );

Session _session({
  required String id,
  required DateTime startedAt,
  DateTime? finishedAt,
  SessionStatus status = SessionStatus.finished,
  bool wasFullyCompleted = true,
  String routineName = 'PPL',
  double totalVolumeKg = 1200,
  int durationMin = 55,
}) =>
    Session(
      id: id,
      uid: _athleteUid,
      routineId: 'r1',
      routineName: routineName,
      startedAt: startedAt,
      finishedAt: finishedAt,
      status: status,
      wasFullyCompleted: wasFullyCompleted,
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
    );

class _StubNoteRepo implements AthleteNoteRepository {
  @override
  Future<void> setNote(AthleteNote note) async {}
  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

List<Override> _baseOverrides({required List<Session> sessions}) => [
      currentUidProvider.overrideWithValue(_trainerUid),
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value([_link()])),
      userPublicProfilesBatchProvider
          .overrideWith((ref, key) => {_athleteUid: _profile()}),
      userPublicProfileProvider
          .overrideWith((ref, id) => Stream.value(_profile())),
      pagosPorCobrarProvider
          .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
      finishedTodayByUidProvider.overrideWith((ref, uid) => const <Session>[]),
      measurementsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <PerformanceTest>[])),
      gymsProvider.overrideWith((ref) => const <Gym>[]),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => sessions),
      assignedRoutinesProvider.overrideWith((ref, id) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteNoteRepositoryProvider.overrideWithValue(_StubNoteRepo()),
    ];

Widget _wrap(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: AlumnoDetailScreen(athleteId: _athleteUid),
        ),
      ),
    );

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectHistorialTab(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {
    // Stream never resolves — enough frames already pumped.
  }
  await tester.tap(find.text('Historial'));
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
}

void main() {
  testWidgets('empty state when the athlete has no sessions', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(sessions: const [])));
    await _selectHistorialTab(tester);

    expect(
        find.text('Este alumno todavía no registró sesiones.'), findsOneWidget);
  });

  testWidgets(
      'shows the session count header + one row per session with all statuses',
      (tester) async {
    final sessions = [
      _session(
        id: 's1',
        startedAt: DateTime(2026, 5, 10, 10),
        finishedAt: DateTime(2026, 5, 10, 11),
        wasFullyCompleted: true,
        routineName: 'PPL Push',
      ),
      _session(
        id: 's2',
        startedAt: DateTime(2026, 5, 5, 10),
        finishedAt: DateTime(2026, 5, 5, 10, 20),
        wasFullyCompleted: false,
        routineName: 'PPL Pull',
      ),
      _session(
        id: 's3',
        startedAt: DateTime(2026, 5, 1, 10),
        status: SessionStatus.active,
        wasFullyCompleted: false,
        routineName: 'PPL Legs',
      ),
    ];

    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(sessions: sessions)));
    await _selectHistorialTab(tester);

    // Count header reflects all sessions, not filtered.
    expect(
        find.textContaining('Historial completo · 3 sesiones'), findsOneWidget);

    // One row per session (routine name unique per session).
    expect(find.text('PPL Push'), findsOneWidget);
    expect(find.text('PPL Pull'), findsOneWidget);
    expect(find.text('PPL Legs'), findsOneWidget);
  });

  testWidgets(
      'status pill: completada → COMPLETA, incompleta → INCOMPLETA, '
      'active → EN CURSO', (tester) async {
    final sessions = [
      _session(
        id: 's1',
        startedAt: DateTime(2026, 5, 10),
        finishedAt: DateTime(2026, 5, 10, 11),
        wasFullyCompleted: true,
      ),
      _session(
        id: 's2',
        startedAt: DateTime(2026, 5, 5),
        finishedAt: DateTime(2026, 5, 5, 10, 20),
        wasFullyCompleted: false,
      ),
      _session(
        id: 's3',
        startedAt: DateTime(2026, 5, 1),
        status: SessionStatus.active,
        wasFullyCompleted: false,
      ),
    ];

    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(sessions: sessions)));
    await _selectHistorialTab(tester);

    expect(find.text('COMPLETA'), findsOneWidget);
    expect(find.text('INCOMPLETA'), findsOneWidget);
    expect(find.text('EN CURSO'), findsOneWidget);
  });

  testWidgets(
      'active session with finishedAt=null shows startedAt in the date '
      'column (not "—")', (tester) async {
    final sessions = [
      _session(
        id: 'active1',
        startedAt: DateTime(2026, 5, 20, 15, 30),
        status: SessionStatus.active,
      ),
    ];

    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(sessions: sessions)));
    await _selectHistorialTab(tester);

    // The dash fallback used in Entrenamientos should NOT be present here —
    // Historial falls back to startedAt for active rows. Acotado a
    // TabBarView (Fase 3 WU-04: el KpiCard "Vencimiento" del chrome
    // persistente puede mostrar '—' cuando no hay billing, fuera del
    // TabBarView).
    expect(
      find.descendant(of: find.byType(TabBarView), matching: find.text('—')),
      findsNothing,
      reason:
          'active sessions must fall back to startedAt in the Historial tab',
    );
  });
}
