// Widget tests for the Coach Hub web "Notas privadas" tab
// (alumno_detail_screen.dart, W2+).
//
// The tab is a private _NotasPrivadasTab class inside alumno_detail_screen —
// we exercise it end-to-end via AlumnoDetailScreen with the Notas tab
// selected, using ProviderScope overrides for the note stream + a stub
// repository that captures setNote calls without hitting Firestore.
//
// Covered:
//   - loading state → CircularProgressIndicator
//   - error state → localized error text
//   - empty note → save disabled until first keystroke
//   - typing + save → repository receives the buffered content
//   - existing note → controller pre-populated + updated-at shown
//   - save while typing does NOT clobber the user's buffer with a stale
//     stream re-emit (the "typing wins" contract)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
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

class _StubNoteRepo implements AthleteNoteRepository {
  _StubNoteRepo();
  final List<AthleteNote> saved = [];

  @override
  Future<void> setNote(AthleteNote note) async {
    saved.add(note);
  }

  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) {
    // Not used — the note stream is overridden at the provider layer.
    return const Stream.empty();
  }
}

List<Override> _baseOverrides({
  required Stream<AthleteNote?> noteStream,
  AthleteNoteRepository? repo,
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
      athleteBillingProvider
          .overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
      assignedRoutinesProvider
          .overrideWith((ref, id) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => noteStream),
      if (repo != null) athleteNoteRepositoryProvider.overrideWithValue(repo),
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

/// Resize the test view to a Coach Hub web-like desktop viewport (1400×900)
/// so the tab bar renders all 10 tabs on-screen and the taps in `_selectNotasTab`
/// actually hit the widget. Auto-restore on tear-down.
void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Selects the "Notas privadas" tab by title. Wraps `pumpAndSettle` in a
/// try/catch because the loading-state test uses a stream that never emits,
/// so pumpAndSettle would time out — swallow the timeout, we've already
/// pumped enough frames for the tab body to lay out.
Future<void> _selectNotasTab(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {
    // Stream never resolves — the frames we've already pumped are enough.
  }
  await tester.tap(find.text('Notas privadas'));
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {
    // Same rationale — tab body is laid out already.
  }
}

void main() {
  testWidgets('loading state shows a spinner', (tester) async {
    // Stream never emits — the note is stuck in loading.
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      noteStream: const Stream.empty(),
    )));
    await _selectNotasTab(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error state shows localized error copy', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      noteStream: Stream.error(StateError('boom')),
    )));
    await _selectNotasTab(tester);

    expect(find.text('No pudimos cargar la nota.'), findsOneWidget);
  });

  testWidgets(
      'empty note → save button is DISABLED until the user types something',
      (tester) async {
    final repo = _StubNoteRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      noteStream: Stream.value(null),
      repo: repo,
    )));
    await _selectNotasTab(tester);

    final saveBtn = find.widgetWithText(ElevatedButton, 'GUARDAR');
    expect(saveBtn, findsOneWidget);
    final button = tester.widget<ElevatedButton>(saveBtn);
    expect(button.onPressed, isNull,
        reason: 'empty tab + empty buffer → nothing to save');
  });

  testWidgets(
      'typing enables save; tapping GUARDAR calls repository with buffer',
      (tester) async {
    final repo = _StubNoteRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      noteStream: Stream.value(null),
      repo: repo,
    )));
    await _selectNotasTab(tester);

    // Type into the tab's TextField. AlumnoDetailScreen has other text fields
    // in siblings tabs; we pick the visible one by its multi-line contract.
    final tf = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 12,
    );
    expect(tf, findsOneWidget);
    await tester.enterText(tf, 'Lesión de rodilla, evitar sentadilla profunda');
    await tester.pump();

    final saveBtn = find.widgetWithText(ElevatedButton, 'GUARDAR');
    final button = tester.widget<ElevatedButton>(saveBtn);
    expect(button.onPressed, isNotNull,
        reason: 'buffer diverges from saved → save must enable');

    await tester.tap(saveBtn);
    await tester.pump();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.trainerId, _trainerUid);
    expect(repo.saved.single.athleteId, _athleteUid);
    expect(repo.saved.single.note,
        'Lesión de rodilla, evitar sentadilla profunda');
  });

  testWidgets(
      'existing note → TextField pre-populated + updated-at line rendered',
      (tester) async {
    final existing = AthleteNote(
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      note: 'Trabaja muy bien con PRs bajos.',
      updatedAt: DateTime(2026, 3, 12, 14, 30),
    );
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      noteStream: Stream.value(existing),
    )));
    await _selectNotasTab(tester);

    // Text is rendered by the TextField controller.
    expect(find.text('Trabaja muy bien con PRs bajos.'), findsOneWidget);
    // Header timestamp uses dd/MM/yyyy · HH:mm — asserted by contains to
    // avoid coupling to the exact separator glyph.
    expect(find.textContaining('12/03/2026'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });

  testWidgets(
      'swapping the athleteId resets the buffer to the new athlete note '
      '(guard: the State is reused across trainers)', (tester) async {
    // The parent (AlumnoDetailScreen) rebuilds with a different athleteId
    // when the trainer navigates roster → detail of another athlete. The
    // internal _NotasPrivadasTabState survives (same widget position) so
    // we must reset the local buffer or the previous athlete's note leaks.
    const otherAthleteUid = 'a2';
    final overrides = <Override>[
      currentUidProvider.overrideWithValue(_trainerUid),
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value([
            _link(),
            TrainerLink(
              id: '${_trainerUid}_$otherAthleteUid',
              trainerId: _trainerUid,
              athleteId: otherAthleteUid,
              status: TrainerLinkStatus.active,
              requestedAt: DateTime(2026, 6, 1),
              acceptedAt: DateTime(2026, 6, 1),
            ),
          ])),
      userPublicProfilesBatchProvider.overrideWith((ref, key) => {
            _athleteUid: _profile(),
            otherAthleteUid: const UserPublicProfile(
                uid: otherAthleteUid, displayName: 'Nico'),
          }),
      userPublicProfileProvider.overrideWith((ref, id) => Stream.value(
          id == _athleteUid
              ? _profile()
              : const UserPublicProfile(
                  uid: otherAthleteUid, displayName: 'Nico'))),
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
      assignedRoutinesProvider.overrideWith((ref, id) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: _athleteUid),
      ).overrideWith((ref) => Stream.value(AthleteNote(
            trainerId: _trainerUid,
            athleteId: _athleteUid,
            note: 'Nota de Sofía.',
            updatedAt: DateTime(2026, 3, 1),
          ))),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: otherAthleteUid),
      ).overrideWith((ref) => Stream.value(AthleteNote(
            trainerId: _trainerUid,
            athleteId: otherAthleteUid,
            note: 'Nota de Nico.',
            updatedAt: DateTime(2026, 3, 2),
          ))),
    ];

    _useDesktopViewport(tester);
    // First render with Sofía's id.
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1400, 900)),
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const _SwappableAlumnoHost(),
        ),
      ),
    ));
    await _selectNotasTab(tester);
    expect(find.text('Nota de Sofía.'), findsOneWidget);

    // Swap the parent to Nico's id. The tab is already selected, so we only
    // need to pump a few frames for the new stream to seed the buffer via
    // didUpdateWidget → _initFromStream.
    final host = tester
        .state<_SwappableAlumnoHostState>(find.byType(_SwappableAlumnoHost));
    host.swap(otherAthleteUid);
    try {
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    } catch (_) {
      // A background stream may still be alive; the frames pumped are enough.
    }

    expect(find.text('Nota de Nico.'), findsOneWidget,
        reason: 'the new athleteId must trigger the buffer to reset and '
            'seed from the new stream');
    expect(find.text('Nota de Sofía.'), findsNothing,
        reason: 'the previous athlete note must NOT leak across the swap');
  });

  testWidgets(
      'typing wins: a re-emit of a stale note does NOT clobber the buffer',
      (tester) async {
    final repo = _StubNoteRepo();
    // Use a broadcast StreamController seeded with an initial empty note so
    // the tab body has data on first paint (otherwise the loading spinner
    // would still be up when we try to enterText).
    final controller = StreamController<AthleteNote?>.broadcast();
    addTearDown(() async {
      await controller.close();
    });
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(
      // Seed with an initial null via a `stream.startWith(null)`-like pattern
      // using an async* generator so the tab pulls a first value on subscribe.
      noteStream: (() async* {
        yield null;
        yield* controller.stream;
      })(),
      repo: repo,
    )));
    await _selectNotasTab(tester);

    final tf = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 12,
    );
    expect(tf, findsOneWidget, reason: 'tab body must be laid out by now');
    await tester.enterText(tf, 'Nota en progreso, no pises.');
    await tester.pump();

    // A stale re-emit arrives (e.g. Firestore snapshot lag).
    controller.add(AthleteNote(
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      note: 'valor viejo del server',
      updatedAt: DateTime(2026, 1, 1),
    ));
    await tester.pump();

    expect(find.text('Nota en progreso, no pises.'), findsOneWidget,
        reason: 'the typing buffer must NOT be overwritten by a stale emit');
    expect(find.text('valor viejo del server'), findsNothing);
  });
}

/// Test host that renders AlumnoDetailScreen with a mutable athleteId so we
/// can simulate the trainer navigating between two alumnos while the tab
/// State is reused.
class _SwappableAlumnoHost extends StatefulWidget {
  const _SwappableAlumnoHost();

  @override
  State<_SwappableAlumnoHost> createState() => _SwappableAlumnoHostState();
}

class _SwappableAlumnoHostState extends State<_SwappableAlumnoHost> {
  String _athleteId = _athleteUid;

  void swap(String next) {
    setState(() => _athleteId = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: AlumnoDetailScreen(athleteId: _athleteId));
  }
}
