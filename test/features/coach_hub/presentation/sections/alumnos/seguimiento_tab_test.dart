// Widget tests for the Coach Hub web "Seguimiento" tab
// (alumno_detail_screen.dart, W2+).
//
// Covered:
//   - empty state
//   - populated list: entries render with tag label + text
//   - tap trash → confirm dialog → repository.delete llamado
//   - cancel confirm dialog → NO delete

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_file_repository.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/data/follow_up_entry_repository.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
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

FollowUpEntry _entry({
  required String id,
  required DateTime recordedAt,
  required String text,
  FollowUpTag tag = FollowUpTag.general,
}) =>
    FollowUpEntry(
      id: id,
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      text: text,
      tag: tag,
      recordedAt: recordedAt,
    );

class _StubNoteRepo implements AthleteNoteRepository {
  @override
  Future<void> setNote(AthleteNote note) async {}
  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

class _StubFileRepo implements AthleteFileRepository {
  @override
  Future<AthleteFile> upload({
    required String trainerId,
    required String athleteId,
    required String fileName,
    required String contentType,
    required dynamic bytes,
  }) async =>
      throw UnimplementedError();
  @override
  Stream<List<AthleteFile>> watch(String trainerId, String athleteId) =>
      const Stream.empty();
  @override
  Future<void> delete(AthleteFile file) async {}
}

class _StubFollowUpRepo implements FollowUpEntryRepository {
  final List<String> deletedIds = [];
  final List<FollowUpEntry> added = [];
  final List<FollowUpEntry> updated = [];

  @override
  Future<FollowUpEntry> add({
    required String trainerId,
    required String athleteId,
    required String text,
    required FollowUpTag tag,
  }) async {
    final e = _entry(
      id: 'stub-${added.length + 1}',
      recordedAt: DateTime(2026, 3, 12),
      text: text,
      tag: tag,
    );
    added.add(e);
    return e;
  }

  @override
  Future<void> update(FollowUpEntry entry) async {
    updated.add(entry);
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
  }

  @override
  Stream<List<FollowUpEntry>> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

List<Override> _baseOverrides({
  required List<FollowUpEntry> entries,
  FollowUpEntryRepository? repo,
}) =>
    [
      currentUidProvider.overrideWithValue(_trainerUid),
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value([_link()])),
      userPublicProfilesBatchProvider
          .overrideWith((ref, key) => {_athleteUid: _profile()}),
      userPublicProfileProvider
          .overrideWith((ref, id) => Stream.value(_profile())),
      pagosPorCobrarProvider
          .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
      finishedTodayByUidProvider
          .overrideWith((ref, uid) => const <Session>[]),
      measurementsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <PerformanceTest>[])),
      gymsProvider.overrideWith((ref) => const <Gym>[]),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
      assignedRoutinesProvider
          .overrideWith((ref, id) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteNoteRepositoryProvider.overrideWithValue(_StubNoteRepo()),
      athleteFilesProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteFileRepositoryProvider.overrideWithValue(_StubFileRepo()),
      followUpEntriesProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => Stream.value(entries)),
      if (repo != null)
        followUpEntryRepositoryProvider.overrideWithValue(repo),
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

Future<void> _selectSeguimientoTab(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
  // "Seguimiento" es tab 9. En viewport 1400 puede estar off-screen a la
  // derecha, saltamos via TabController como en mediciones.
  final tabBarContext = tester.element(find.byType(TabBar));
  DefaultTabController.of(tabBarContext).animateTo(9);
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
}

void main() {
  testWidgets('empty state cuando no hay entradas', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(entries: const [])));
    await _selectSeguimientoTab(tester);

    expect(
      find.text('No hay entradas de seguimiento todavía.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'populated list renderiza cada entrada con tag chip y texto',
      (tester) async {
    final entries = [
      _entry(
        id: 'e1',
        recordedAt: DateTime(2026, 3, 12),
        text: 'Cambio a bloque de fuerza',
        tag: FollowUpTag.entrenamiento,
      ),
      _entry(
        id: 'e2',
        recordedAt: DateTime(2026, 3, 5),
        text: 'Le duele el hombro',
        tag: FollowUpTag.molestia,
      ),
    ];
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(entries: entries)));
    await _selectSeguimientoTab(tester);

    expect(find.text('Cambio a bloque de fuerza'), findsOneWidget);
    expect(find.text('Le duele el hombro'), findsOneWidget);
    // Tags como chip labels.
    expect(find.text('ENTRENAMIENTO'), findsOneWidget);
    expect(find.text('MOLESTIA'), findsOneWidget);
  });

  testWidgets(
      'tap en trash → confirm dialog → repository.delete llamado',
      (tester) async {
    final e = _entry(
      id: 'e1',
      recordedAt: DateTime(2026, 3, 12),
      text: 'Hola',
    );
    final repo = _StubFollowUpRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(entries: [e], repo: repo),
    ));
    await _selectSeguimientoTab(tester);

    final trash = find.byIcon(TreinoIcon.trash);
    expect(trash, findsOneWidget);
    await tester.tap(trash);
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar entrada?'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['e1']);
  });

  testWidgets(
      'cancelar el confirm dialog NO llama repository.delete',
      (tester) async {
    final e = _entry(
      id: 'e1',
      recordedAt: DateTime(2026, 3, 12),
      text: 'Hola',
    );
    final repo = _StubFollowUpRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(entries: [e], repo: repo),
    ));
    await _selectSeguimientoTab(tester);

    await tester.tap(find.byIcon(TreinoIcon.trash));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty);
  });
}
