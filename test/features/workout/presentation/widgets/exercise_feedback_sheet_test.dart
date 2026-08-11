import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show currentAthleteLinkProvider, sessionShareRepositoryProvider;
import 'package:treino/features/coach/data/session_share_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/exercise_feedback_providers.dart';
import 'package:treino/features/workout/data/exercise_feedback_repository.dart';
import 'package:treino/features/workout/domain/exercise_feedback_kind.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_feedback_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'athlete-1';
const _sessionId = 'session-1';
const _trainerId = 'trainer-9';

TrainerLink _link() => TrainerLink(
      id: 'link-1',
      trainerId: _trainerId,
      athleteId: _uid,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 8, 1),
    );

Widget _wrap({
  required FakeFirebaseFirestore firestore,
  TrainerLink? link,
  int? setNumber,
}) {
  return ProviderScope(
    overrides: [
      exerciseFeedbackRepositoryProvider.overrideWithValue(
        ExerciseFeedbackRepository(firestore: firestore),
      ),
      sessionShareRepositoryProvider.overrideWithValue(
        SessionShareRepository(firestore: firestore),
      ),
      currentAthleteLinkProvider.overrideWith((_) async => link),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: ExerciseFeedbackSheet(
          uid: _uid,
          sessionId: _sessionId,
          exerciseId: 'ex-bench',
          exerciseName: 'Press banca',
          slotIndex: 0,
          setNumber: setNumber,
        ),
      ),
    ),
  );
}

Future<List<Map<String, Object?>>> _written(
  FakeFirebaseFirestore firestore,
) async {
  final snap = await firestore
      .collection('users')
      .doc(_uid)
      .collection('sessions')
      .doc(_sessionId)
      .collection('exerciseFeedback')
      .get();
  return snap.docs.map((d) => d.data()).toList();
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  group('ExerciseFeedbackSheet', () {
    testWidgets('shows the exercise and set it is anchored to', (tester) async {
      await tester.pumpWidget(
        _wrap(firestore: firestore, link: _link(), setNumber: 3),
      );
      await tester.pump();

      expect(find.textContaining('Press banca'), findsWidgets);
      expect(find.textContaining('serie 3'), findsOneWidget);
    });

    testWidgets('defaults to the comment kind', (tester) async {
      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      final chip = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text('Comentario'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(chip.properties.selected, isTrue);
    });

    testWidgets('refuses to send with an empty text field', (tester) async {
      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exercise_feedback_error')), findsOneWidget);
      expect(await _written(firestore), isEmpty);
    });

    testWidgets('writes a comment and pops with the kind', (tester) async {
      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'Me tiró el hombro',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      final docs = await _written(firestore);
      expect(docs, hasLength(1));
      expect(docs.single['text'], 'Me tiró el hombro');
      expect(docs.single['kind'], 'comment');
    });

    testWidgets('selecting discomfort persists that kind', (tester) async {
      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      await tester
          .tap(find.byKey(const Key('exercise_feedback_kind_discomfort')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'Dolor en la rodilla',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      final docs = await _written(firestore);
      expect(docs.single['kind'], 'discomfort');
    });

    testWidgets('anchors the entry to exerciseId, slotIndex and setNumber',
        (tester) async {
      await tester.pumpWidget(
        _wrap(firestore: firestore, link: _link(), setNumber: 2),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'anchored',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      final doc = (await _written(firestore)).single;
      expect(doc['exerciseId'], 'ex-bench');
      expect(doc['slotIndex'], 0);
      expect(doc['setNumber'], 2);
    });

    testWidgets('grants session_shares on first send when linked',
        (tester) async {
      // Consent at the moment of peak motivation: the athlete just wrote that
      // something hurts, and the trainer must be able to read it.
      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'hombro',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      final share =
          await firestore.collection('session_shares').doc(_uid).get();
      expect(share.exists, isTrue);
      expect(share.data()!['trainerId'], _trainerId);
    });

    testWidgets('does not write when the athlete has no linked trainer',
        (tester) async {
      // Nobody to grant to — say so instead of writing into a void.
      await tester.pumpWidget(_wrap(firestore: firestore, link: null));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'sin PF',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exercise_feedback_error')), findsOneWidget);
      expect(await _written(firestore), isEmpty);
    });

    testWidgets('an existing grant is not overwritten', (tester) async {
      await firestore
          .collection('session_shares')
          .doc(_uid)
          .set({'trainerId': 'already-granted'});

      await tester.pumpWidget(_wrap(firestore: firestore, link: _link()));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('exercise_feedback_text_field')),
        'ok',
      );
      await tester.tap(find.text('ENVIAR'));
      await tester.pumpAndSettle();

      final share =
          await firestore.collection('session_shares').doc(_uid).get();
      expect(share.data()!['trainerId'], 'already-granted');
      expect(await _written(firestore), hasLength(1));
    });
  });

  group('ExerciseFeedbackSubmission', () {
    test('carries the kind so the caller can pick the right confirmation', () {
      const submission = ExerciseFeedbackSubmission(
        kind: ExerciseFeedbackKind.discomfort,
      );
      expect(submission.kind.notifiesTrainer, isTrue);
    });
  });
}
