import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// NOTA DEL ALUMNO is edited IN PLACE. It used to be a read-only card plus an
// "Agregar"/"Editar" link that opened a bottom sheet — a detour to type one
// line of text. Tapping the card is the gesture it already looked like it
// supported.

const _kTrainer = 'trainer-1';
const _kAthlete = 'athlete-1';

class _RecordingNoteRepo implements AthleteNoteRepository {
  final List<AthleteNote> saved = [];
  bool throwOnSave = false;

  @override
  Future<void> setNote(AthleteNote note) async {
    if (throwOnSave) throw Exception('firestore down');
    saved.add(note);
  }

  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

AthleteNote _note(String text) => AthleteNote(
      trainerId: _kTrainer,
      athleteId: _kAthlete,
      note: text,
      updatedAt: DateTime.utc(2026, 7, 29),
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AthleteNote? existing,
  required AthleteNoteRepository repo,
}) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/$_kAthlete',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            Scaffold(body: child, bottomNavigationBar: const SizedBox()),
        routes: [
          GoRoute(
            path: '/coach/athlete/:athleteId',
            builder: (context, state) => AthleteDetailScreen(
              athleteId: state.pathParameters['athleteId']!,
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userPublicProfileProvider(_kAthlete).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: _kAthlete, displayName: 'Martín G'),
          ),
        ),
        assignedRoutinesProvider(_kAthlete)
            .overrideWith((ref) async => const []),
        athleteNoteRepositoryProvider.overrideWithValue(repo),
        athleteNoteProvider((trainerId: _kTrainer, athleteId: _kAthlete))
            .overrideWith((ref) => Stream.value(existing)),
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
}

/// The section lives near the bottom of a long ListView.
Future<void> _scrollToNota(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('NOTA DEL ALUMNO'),
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pump();
}

void main() {
  group('AthleteDetailScreen — NOTA DEL ALUMNO inline', () {
    testWidgets('the old Agregar/Editar link is gone', (tester) async {
      await _pumpScreen(
        tester,
        existing: _note('Viene entrenando bien'),
        repo: _RecordingNoteRepo(),
      );
      await _scrollToNota(tester);

      expect(find.text('Editar'), findsNothing);
      expect(find.text('Agregar'), findsNothing);
    });

    testWidgets('empty note shows a hint that doubles as the affordance',
        (tester) async {
      await _pumpScreen(tester, existing: null, repo: _RecordingNoteRepo());
      await _scrollToNota(tester);

      // With no link left, the copy has to say what to do.
      expect(find.text('Tocá para escribir una nota.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
        'tapping the card turns it into the field, seeded with the note',
        (tester) async {
      await _pumpScreen(
        tester,
        existing: _note('Viene entrenando bien'),
        repo: _RecordingNoteRepo(),
      );
      await _scrollToNota(tester);

      await tester.tap(find.text('Viene entrenando bien'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, equals('Viene entrenando bien'));
      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    // The section sits at the BOTTOM of a long ListView: entering edit mode
    // grows the card and used to push Cancelar/Guardar past the fold, so the
    // trainer tapped to write and the way to confirm was off-screen. Flutter
    // auto-scrolls the focused field into view but stops there — the buttons
    // below it are what need the extra room.
    testWidgets('entering edit mode scrolls Cancelar/Guardar into view',
        (tester) async {
      await _pumpScreen(
        tester,
        existing: _note('una nota'),
        repo: _RecordingNoteRepo(),
      );
      await _scrollToNota(tester);

      await tester.tap(find.text('una nota'));
      await tester.pumpAndSettle();

      final viewport = tester.getSize(find.byType(MaterialApp));
      for (final label in ['Cancelar', 'Guardar']) {
        final rect = tester.getRect(find.text(label));
        expect(
          rect.bottom,
          lessThanOrEqualTo(viewport.height),
          reason: '$label quedó abajo del fold',
        );
        expect(rect.top, greaterThanOrEqualTo(0));
      }
    });

    testWidgets('saving persists the trimmed text and leaves edit mode',
        (tester) async {
      final repo = _RecordingNoteRepo();
      await _pumpScreen(tester, existing: _note('viejo'), repo: repo);
      await _scrollToNota(tester);

      await tester.tap(find.text('viejo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  texto nuevo  ');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repo.saved, hasLength(1));
      expect(repo.saved.single.note, equals('texto nuevo'));
      expect(repo.saved.single.trainerId, equals(_kTrainer));
      expect(repo.saved.single.athleteId, equals(_kAthlete));
      // Back to read mode.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('cancelling discards the edit and writes nothing',
        (tester) async {
      final repo = _RecordingNoteRepo();
      await _pumpScreen(tester, existing: _note('original'), repo: repo);
      await _scrollToNota(tester);

      await tester.tap(find.text('original'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'descartame');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.saved, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('original'), findsOneWidget);
    });

    testWidgets('a failed save keeps edit mode AND the typed text',
        (tester) async {
      final repo = _RecordingNoteRepo()..throwOnSave = true;
      await _pumpScreen(tester, existing: null, repo: repo);
      await _scrollToNota(tester);

      await tester.tap(find.text('Tocá para escribir una nota.'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no me pierdas');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repo.saved, isEmpty);
      expect(find.text('No pudimos guardar. Probá de nuevo.'), findsOneWidget);
      // The trainer must not have to retype after a failed write.
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        equals('no me pierdas'),
      );
    });
  });
}
