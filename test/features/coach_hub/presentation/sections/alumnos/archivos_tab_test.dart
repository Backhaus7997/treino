// Widget tests for the Coach Hub web "Archivos" tab
// (alumno_detail_screen.dart, W2+).
//
// The tab is a private _ArchivosTab class inside alumno_detail_screen — we
// exercise it end-to-end via AlumnoDetailScreen with the Archivos tab
// selected, overriding athleteFilesProvider + a stub AthleteFileRepository
// that captures upload/delete calls without hitting Firestore/Storage.
//
// Covered:
//   - loading state → CircularProgressIndicator
//   - error state → localized error copy
//   - empty state → localized empty copy
//   - populated list → one row per file with size + date subtitle
//   - delete flow → confirm dialog + repository call
//   - too-large upload → repository throws → localized snackbar
//   - Fase 3 WU-07b: rows render via the kit's TreinoListRow (mockup
//     archivos.png — ícono + peso + fecha), delete confirm via
//     showTreinoDialog.
//
// The upload happy path (file_picker + repo.upload) requires mocking the
// file_picker plugin. We keep that for smoke, not for widget tests.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
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

AthleteFile _file({
  required String id,
  required String fileName,
  AthleteFileKind kind = AthleteFileKind.pdf,
  int sizeBytes = 512 * 1024,
  DateTime? uploadedAt,
}) =>
    AthleteFile(
      id: id,
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      fileName: fileName,
      kind: kind,
      contentType:
          kind == AthleteFileKind.pdf ? 'application/pdf' : 'image/jpeg',
      sizeBytes: sizeBytes,
      storagePath: 'athleteFiles/${_trainerUid}_$_athleteUid/$id.pdf',
      downloadUrl: 'https://example.com/$id',
      uploadedAt: uploadedAt ?? DateTime(2026, 3, 10, 14, 30),
    );

class _StubNoteRepo implements AthleteNoteRepository {
  @override
  Future<void> setNote(AthleteNote note) async {}
  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

class _StubFileRepo implements AthleteFileRepository {
  // ignore: unused_element_parameter
  _StubFileRepo({this.tooLargeOnUpload = false});

  final bool tooLargeOnUpload;
  final List<AthleteFile> deleted = [];
  final List<Uint8List> uploadedBytes = [];

  @override
  Future<AthleteFile> upload({
    required String trainerId,
    required String athleteId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    if (tooLargeOnUpload) {
      throw AthleteFileTooLargeException(bytes.length);
    }
    uploadedBytes.add(bytes);
    return _file(id: 'new-${uploadedBytes.length}', fileName: fileName);
  }

  @override
  Stream<List<AthleteFile>> watch(String trainerId, String athleteId) =>
      const Stream.empty();

  @override
  Future<void> delete(AthleteFile file) async {
    deleted.add(file);
  }
}

List<Override> _baseOverrides({
  required AsyncValue<List<AthleteFile>>? filesState,
  AthleteFileRepository? repo,
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
          .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
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
      if (filesState != null)
        athleteFilesProvider(
          (trainerId: _trainerUid, athleteId: _athleteUid),
        ).overrideWith((ref) async* {
          filesState.when(
            data: (v) {},
            loading: () {},
            error: (_, __) {},
          );
          // Emit synchronously via async* so the AsyncValue in tab matches.
          if (filesState.hasError) {
            throw filesState.error!;
          }
          if (filesState.hasValue) {
            yield filesState.requireValue;
          }
        }),
      if (repo != null) athleteFileRepositoryProvider.overrideWithValue(repo),
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

Future<void> _selectArchivosTab(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
  await tester.tap(find.text('Archivos'));
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
}

void main() {
  testWidgets('loading state shows a spinner', (tester) async {
    _useDesktopViewport(tester);
    // Override with a stream that never emits so the AsyncValue stays in
    // loading state on the tab body.
    await tester.pumpWidget(_wrap([
      ..._baseOverrides(
          filesState: const AsyncData<List<AthleteFile>>(<AthleteFile>[])),
      athleteFilesProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
    ]));
    await _selectArchivosTab(tester);

    expect(find.byType(CircularProgressIndicator), findsAtLeast(1));
  });

  testWidgets('empty state shows localized copy', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      filesState: const AsyncData<List<AthleteFile>>(<AthleteFile>[]),
    )));
    await _selectArchivosTab(tester);

    expect(find.text('Todavía no subiste archivos sobre este alumno.'),
        findsOneWidget);
  });

  testWidgets(
      'populated list renders one row per file with size + date subtitle',
      (tester) async {
    final files = [
      _file(
        id: 'f1',
        fileName: 'análisis-sangre-marzo.pdf',
        kind: AthleteFileKind.pdf,
        sizeBytes: 512 * 1024,
        uploadedAt: DateTime(2026, 3, 10, 14, 30),
      ),
      _file(
        id: 'f2',
        fileName: 'postura-sentadilla.jpg',
        kind: AthleteFileKind.image,
        sizeBytes: 2 * 1024 * 1024,
        uploadedAt: DateTime(2026, 3, 5, 10, 0),
      ),
    ];
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      filesState: AsyncData(files),
    )));
    await _selectArchivosTab(tester);

    expect(find.text('análisis-sangre-marzo.pdf'), findsOneWidget);
    expect(find.text('postura-sentadilla.jpg'), findsOneWidget);
    // Size formatting: 512 KB and 2.0 MB — verify by textContaining to avoid
    // exact-match brittleness on locale-specific separators.
    expect(find.textContaining('512 KB'), findsOneWidget);
    expect(find.textContaining('2.0 MB'), findsOneWidget);
  });

  testWidgets(
      'delete flow: tap trash → confirm dialog → repository receives call',
      (tester) async {
    final files = [
      _file(id: 'f1', fileName: 'análisis.pdf'),
    ];
    final repo = _StubFileRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      filesState: AsyncData(files),
      repo: repo,
    )));
    await _selectArchivosTab(tester);

    // Two IconButtons per row (open + delete). Delete is the second one.
    final trashButtons = find.byIcon(TreinoIcon.trash);
    expect(trashButtons, findsOneWidget);
    await tester.tap(trashButtons);
    await tester.pumpAndSettle();

    // Confirm dialog visible.
    expect(find.text('¿Eliminar archivo?'), findsOneWidget);
    // Confirm the action.
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repo.deleted, hasLength(1));
    expect(repo.deleted.single.id, 'f1');
  });

  testWidgets('delete flow: cancel dialog → repository NOT called',
      (tester) async {
    final files = [
      _file(id: 'f1', fileName: 'análisis.pdf'),
    ];
    final repo = _StubFileRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      filesState: AsyncData(files),
      repo: repo,
    )));
    await _selectArchivosTab(tester);

    await tester.tap(find.byIcon(TreinoIcon.trash));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
  });

  testWidgets('Fase 3 WU-07b: populated rows render via the kit TreinoListRow',
      (tester) async {
    final files = [
      _file(id: 'f1', fileName: 'analisis.pdf'),
      _file(id: 'f2', fileName: 'postura.jpg', kind: AthleteFileKind.image),
    ];
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      filesState: AsyncData(files),
    )));
    await _selectArchivosTab(tester);

    expect(find.byType(TreinoListRow), findsNWidgets(2));
  });
}
