import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/trained_today_provider.dart';
import 'package:treino/features/coach/data/follow_up_entry_repository.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

// The "Dejar feedback" link in the ENTRENARON HOY section had NO handler: the
// mockup shows it as an active accent link but no destination screen was ever
// designed, so `_SectionHeader` rendered it muted and inert. It now opens a
// two-step sheet — pick an athlete who trained today, write the note — that
// persists a FollowUpEntry tagged `entrenamiento`, the same private
// trainer→athlete note the Coach Hub (web) already creates.

// ── Fakes ────────────────────────────────────────────────────────────────────

class _RecordingRepo implements FollowUpEntryRepository {
  final List<FollowUpEntry> added = [];
  bool throwOnAdd = false;

  @override
  Future<FollowUpEntry> add({
    required String trainerId,
    required String athleteId,
    required String text,
    required FollowUpTag tag,
  }) async {
    if (throwOnAdd) throw Exception('firestore down');
    final entry = FollowUpEntry(
      id: 'e1',
      trainerId: trainerId,
      athleteId: athleteId,
      text: text,
      tag: tag,
      recordedAt: DateTime.utc(2026, 7, 28),
    );
    added.add(entry);
    return entry;
  }

  @override
  Stream<List<FollowUpEntry>> watch(String trainerId, String athleteId) =>
      const Stream.empty();

  @override
  Future<void> update(FollowUpEntry entry) async {}

  @override
  Future<void> delete(String id) async {}
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

Session _session(String uid) => Session(
      id: 's-$uid',
      uid: uid,
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 10),
      finishedAt: DateTime.utc(2026, 7, 28, 11),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

TrainedTodayEntry _entry(String uid) =>
    TrainedTodayEntry(athleteId: uid, session: _session(uid));

Widget _wrap({
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: DejarFeedbackSheetTestHarness()),
      ),
    );

List<Override> _overrides({
  required List<TrainedTodayEntry> today,
  required FollowUpEntryRepository repo,
  String trainerId = 't1',
}) =>
    [
      currentUidProvider.overrideWithValue(trainerId),
      trainedTodayProvider.overrideWithValue(AsyncValue.data(today)),
      followUpEntryRepositoryProvider.overrideWithValue(repo),
      userPublicProfileProvider('a1').overrideWith(
        (_) => Stream.value(
          const UserPublicProfile(uid: 'a1', displayName: 'Lucía Fernández'),
        ),
      ),
      userPublicProfileProvider('a2').overrideWith(
        (_) => Stream.value(
          const UserPublicProfile(uid: 'a2', displayName: 'Diego Torres'),
        ),
      ),
    ];

void main() {
  group('Dejar feedback sheet', () {
    testWidgets('step 1 lists the athletes who trained today', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _overrides(
          today: [_entry('a1'), _entry('a2')],
          repo: _RecordingRepo(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Lucía Fernández'), findsOneWidget);
      expect(find.text('Diego Torres'), findsOneWidget);
      // Composer not shown until an athlete is picked.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('nobody trained today → empty state, no composer',
        (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _overrides(today: const [], repo: _RecordingRepo()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nadie entrenó hoy todavía.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('picking an athlete opens the composer titled with their name',
        (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _overrides(
          today: [_entry('a1'), _entry('a2')],
          repo: _RecordingRepo(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Lucía Fernández'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      // The picked athlete replaces the sheet title, and the other athlete is
      // gone — the picker was swapped out, not stacked under the composer.
      expect(find.text('Lucía Fernández'), findsOneWidget);
      expect(find.text('Diego Torres'), findsNothing);
    });

    testWidgets('save is disabled until the note has text', (tester) async {
      final repo = _RecordingRepo();
      await tester.pumpWidget(_wrap(
        overrides: _overrides(today: [_entry('a1')], repo: repo),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lucía Fernández'));
      await tester.pumpAndSettle();

      FilledButton saveButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));

      expect(saveButton().onPressed, isNull, reason: 'empty note → disabled');

      // Whitespace alone must not enable it either.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(saveButton().onPressed, isNull, reason: 'blank note → disabled');

      await tester.enterText(find.byType(TextField), 'Buen trabajo hoy');
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);
    });

    testWidgets('saving writes a FollowUpEntry tagged entrenamiento',
        (tester) async {
      final repo = _RecordingRepo();
      await tester.pumpWidget(_wrap(
        overrides: _overrides(today: [_entry('a1')], repo: repo),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lucía Fernández'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  Buen trabajo hoy  ');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(repo.added, hasLength(1));
      final saved = repo.added.single;
      expect(saved.trainerId, equals('t1'));
      expect(saved.athleteId, equals('a1'));
      // Trimmed — leading/trailing whitespace is not part of the note.
      expect(saved.text, equals('Buen trabajo hoy'));
      expect(saved.tag, equals(FollowUpTag.entrenamiento));
    });

    testWidgets('a failed write keeps the sheet open and shows the error',
        (tester) async {
      final repo = _RecordingRepo()..throwOnAdd = true;
      await tester.pumpWidget(_wrap(
        overrides: _overrides(today: [_entry('a1')], repo: repo),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lucía Fernández'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Buen trabajo');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(repo.added, isEmpty);
      expect(
        find.text('No pudimos guardar el feedback. Probá de nuevo.'),
        findsOneWidget,
      );
      // The note is NOT lost — the trainer can retry without retyping.
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        equals('Buen trabajo'),
      );
    });

    testWidgets('back from the composer returns to the picker', (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: _overrides(
          today: [_entry('a1'), _entry('a2')],
          repo: _RecordingRepo(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lucía Fernández'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(TreinoIcon.back));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Diego Torres'), findsOneWidget);
    });
  });
}
