// Widget tests for the Coach Hub web "Mediciones" tab
// (alumno_detail_screen.dart, W2+).
//
// El tab es una clase privada _MedicionesTab en alumno_detail_screen — la
// ejercitamos end-to-end via AlumnoDetailScreen con la tab seleccionada,
// overriding measurementsForAthleteProvider con un stub y stubeando el
// repository para capturar delete calls sin tocar Firestore.
//
// Covered:
//   - empty state: mensaje "sin mediciones"
//   - populated list: una row por medición con summary line
//   - tap en row → expande y muestra detalle
//   - tap en trash → confirm dialog → repository.delete llamado
//   - cancelar dialog → repository NO llamado
//
// El upload happy path (dialog nueva medición + form + save) requiere ejercitar
// muchos TextFields y no aporta mucho en widget test — se cubre por smoke.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_file_repository.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
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

Measurement _measurement({
  required String id,
  required DateTime recordedAt,
  double? weightKg,
  double? fatPercentage,
  double? waistCm,
}) =>
    Measurement(
      id: id,
      athleteId: _athleteUid,
      recordedBy: _trainerUid,
      recordedAt: recordedAt,
      weightKg: weightKg,
      fatPercentage: fatPercentage,
      waistCm: waistCm,
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

class _StubMeasurementRepo implements MeasurementRepository {
  final List<String> deletedIds = [];
  final List<Measurement> added = [];
  final List<Measurement> updated = [];

  @override
  Future<Measurement> add(Measurement m) async {
    added.add(m);
    return m;
  }

  @override
  Future<void> update(Measurement m) async {
    updated.add(m);
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
  }

  @override
  Stream<List<Measurement>> watchRecordedBy(String trainerUid) =>
      const Stream.empty();

  @override
  Stream<List<Measurement>> watchForAthlete(String athleteId) =>
      const Stream.empty();

  @override
  Stream<List<Measurement>> watchForTrainerAthlete(
    String trainerUid,
    String athleteId,
  ) =>
      const Stream.empty();
}

List<Override> _baseOverrides({
  required List<Measurement> measurements,
  MeasurementRepository? repo,
}) =>
    [
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
          .overrideWith((ref, id) => Stream.value(measurements)),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <PerformanceTest>[])),
      gymsProvider.overrideWith((ref) => const <Gym>[]),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
      assignedRoutinesProvider.overrideWith((ref, id) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteNoteRepositoryProvider.overrideWithValue(_StubNoteRepo()),
      athleteFilesProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteFileRepositoryProvider.overrideWithValue(_StubFileRepo()),
      if (repo != null) measurementRepositoryProvider.overrideWithValue(repo),
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

Future<void> _selectMedicionesTab(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
  // "Mediciones" es el tab #10 (último). En viewport 1400 el TabBar hace
  // scroll horizontal; el tab queda off-screen a la derecha así que `tap`
  // no llega. Usamos el DefaultTabController del BuildContext del TabBar
  // para saltar al índice 10 directamente.
  final tabBarContext = tester.element(find.byType(TabBar));
  DefaultTabController.of(tabBarContext).animateTo(10);
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
}

void main() {
  testWidgets('empty state cuando no hay mediciones', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(measurements: const [])));
    await _selectMedicionesTab(tester);

    expect(
      find.text('Este alumno todavía no tiene mediciones cargadas.'),
      findsOneWidget,
    );
  });

  testWidgets('populated list: una row por medición con summary',
      (tester) async {
    final measurements = [
      _measurement(
        id: 'm1',
        recordedAt: DateTime(2026, 3, 12),
        weightKg: 78,
        fatPercentage: 15,
      ),
      _measurement(
        id: 'm2',
        recordedAt: DateTime(2026, 2, 5),
        weightKg: 80,
        waistCm: 82,
      ),
    ];
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(measurements: measurements)));
    await _selectMedicionesTab(tester);

    // Summary de m1 → peso + %grasa (double `78` renderiza como "78.0")
    expect(find.textContaining('78.0 kg'), findsOneWidget);
    expect(find.textContaining('15.0% grasa'), findsOneWidget);
    // Summary de m2 → peso + cintura
    expect(find.textContaining('80.0 kg'), findsOneWidget);
    expect(find.textContaining('cintura 82.0 cm'), findsOneWidget);
  });

  testWidgets('tap en row expande el detalle con todos los campos cargados',
      (tester) async {
    final m = _measurement(
      id: 'm1',
      recordedAt: DateTime(2026, 3, 12),
      weightKg: 78,
      fatPercentage: 15,
      waistCm: 82,
    );
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(measurements: [m])));
    await _selectMedicionesTab(tester);

    // Antes del tap: solo summary visible.
    expect(find.textContaining('78.0 kg'), findsOneWidget);

    // Tap en la row (usa el chevron).
    await tester.tap(find.byIcon(TreinoIcon.chevronRight));
    await tester.pumpAndSettle();

    // Post-expansión: aparecen labels del detalle.
    expect(find.text('Peso'), findsOneWidget);
    expect(find.text('% grasa'), findsOneWidget);
    expect(find.text('Cintura'), findsOneWidget);
  });

  testWidgets('tap en trash → confirm dialog → repository.delete llamado',
      (tester) async {
    final m = _measurement(
      id: 'm1',
      recordedAt: DateTime(2026, 3, 12),
      weightKg: 78,
    );
    final repo = _StubMeasurementRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(measurements: [m], repo: repo),
    ));
    await _selectMedicionesTab(tester);

    // Debería haber exactamente un trash button en la row.
    final trash = find.byIcon(TreinoIcon.trash);
    expect(trash, findsOneWidget);
    await tester.tap(trash);
    await tester.pumpAndSettle();

    // Confirm dialog visible.
    expect(find.text('¿Eliminar medición?'), findsOneWidget);
    // Tap Confirmar.
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['m1']);
  });

  testWidgets('cancelar el confirm dialog NO llama repository.delete',
      (tester) async {
    final m = _measurement(
      id: 'm1',
      recordedAt: DateTime(2026, 3, 12),
      weightKg: 78,
    );
    final repo = _StubMeasurementRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(measurements: [m], repo: repo),
    ));
    await _selectMedicionesTab(tester);

    await tester.tap(find.byIcon(TreinoIcon.trash));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty);
  });

  // ── PR#2: Toggle + subvista Rendimiento ─────────────────────────────────

  testWidgets(
      'toggle Rendimiento cambia el header y muestra empty state de pruebas',
      (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(measurements: const [])));
    await _selectMedicionesTab(tester);

    // Antes del toggle: header antropométrico.
    expect(find.text('Mediciones antropométricas'), findsOneWidget);
    expect(find.text('Pruebas de rendimiento'), findsNothing);

    // Toggle a Rendimiento.
    await tester.tap(find.text('RENDIMIENTO'));
    await tester.pumpAndSettle();

    // Post-toggle: header rendimiento + empty state de pruebas.
    expect(find.text('Pruebas de rendimiento'), findsOneWidget);
    expect(find.text('Mediciones antropométricas'), findsNothing);
    expect(
      find.text(
          'Este alumno todavía no tiene pruebas de rendimiento cargadas.'),
      findsOneWidget,
    );
    // Botón de CTA cambia label.
    expect(find.text('NUEVA PRUEBA'), findsOneWidget);
  });

  // ── PR#3: Editar ────────────────────────────────────────────────────────

  testWidgets(
      'tap en editar abre el dialog con título "Editar medición" '
      'y pre-populado con los valores', (tester) async {
    final m = _measurement(
      id: 'm1',
      recordedAt: DateTime(2026, 3, 12),
      weightKg: 78,
      fatPercentage: 15,
    );
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(measurements: [m])));
    await _selectMedicionesTab(tester);

    // Botón editar (TreinoIcon.edit) en la row.
    final editBtn = find.byIcon(TreinoIcon.edit);
    expect(editBtn, findsOneWidget);
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    // Dialog en modo edición.
    expect(find.text('Editar medición'), findsOneWidget);
    // Los valores del form deberían estar pre-populados. El TextFormField
    // renderiza los valores existentes en el widget tree.
    expect(find.text('78.0'), findsOneWidget);
    expect(find.text('15.0'), findsOneWidget);
  });

  testWidgets('save en modo edición llama repository.update (no add)',
      (tester) async {
    final m = _measurement(
      id: 'm1',
      recordedAt: DateTime(2026, 3, 12),
      weightKg: 78,
    );
    final repo = _StubMeasurementRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(measurements: [m], repo: repo),
    ));
    await _selectMedicionesTab(tester);
    await tester.tap(find.byIcon(TreinoIcon.edit));
    await tester.pumpAndSettle();

    // Tap en el botón GUARDAR del dialog (TreinoDialog primary action).
    await tester.tap(find.byKey(const Key('dialog_primary_button')));
    await tester.pumpAndSettle();

    // Debería haber llamado update, NO add.
    expect(repo.updated, hasLength(1));
    expect(repo.updated.single.id, 'm1',
        reason: 'update debe preservar el id original');
    expect(repo.added, isEmpty);
  });

  testWidgets('subvista Rendimiento muestra pruebas con summary line',
      (tester) async {
    final tests = [
      PerformanceTest(
        id: 't1',
        athleteId: _athleteUid,
        recordedBy: _trainerUid,
        recordedAt: DateTime(2026, 3, 12),
        cmjCm: 42,
        sprint10mS: 1.6,
        squat1rmKg: 120,
      ),
    ];
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap([
      ..._baseOverrides(measurements: const []),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(tests)),
    ]));
    await _selectMedicionesTab(tester);
    await tester.tap(find.text('RENDIMIENTO'));
    await tester.pumpAndSettle();

    // Summary line muestra los 3 markers: CMJ, Sprint 10m, Sentadilla 1RM.
    expect(find.textContaining('CMJ 42.0 cm'), findsOneWidget);
    expect(find.textContaining('10m 1.6s'), findsOneWidget);
    expect(find.textContaining('Sent. 120.0 kg'), findsOneWidget);
  });
}
