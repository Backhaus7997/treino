import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/template_rating.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RoutineRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RoutineRepository(firestore: firestore);
  });

  Future<void> seedRoutine(
    String id, {
    required String source,
    required String visibility,
    String? assignedBy,
    String? createdBy,
  }) async {
    await firestore.collection('routines').doc(id).set({
      'name': 'Seed $id',
      'level': 'beginner',
      'days': <Object?>[],
      'numWeeks': 1,
      'source': source,
      'visibility': visibility,
      if (assignedBy != null) 'assignedBy': assignedBy,
      'assignedTo': null,
      if (createdBy != null) 'createdBy': createdBy,
      'status': 'active',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
  }

  TemplateRating makeRating(
    String uid, {
    int rating = 4,
    String? comment,
    int createdMs = 1000,
  }) =>
      TemplateRating(
        userId: uid,
        rating: rating,
        comment: comment,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      );

  group('publishTemplate / unpublishTemplate', () {
    test('publishTemplate flips ONLY visibility to public', () async {
      await seedRoutine(
        'tpl-1',
        source: 'trainer-template',
        visibility: 'private',
        assignedBy: 'trainer-a',
      );

      await repo.publishTemplate('tpl-1');

      final data =
          (await firestore.collection('routines').doc('tpl-1').get()).data()!;
      expect(data['visibility'], 'public');
      // Narrow single-field update — nothing else may drift.
      expect(data['name'], 'Seed tpl-1');
      expect(data['source'], 'trainer-template');
      expect(data['assignedBy'], 'trainer-a');
      expect(data['status'], 'active');
    });

    test('unpublishTemplate flips visibility back to private', () async {
      await seedRoutine(
        'tpl-1',
        source: 'trainer-template',
        visibility: 'public',
        assignedBy: 'trainer-a',
      );

      await repo.unpublishTemplate('tpl-1');

      final data =
          (await firestore.collection('routines').doc('tpl-1').get()).data()!;
      expect(data['visibility'], 'private');
    });

    test('empty template id throws ArgumentError', () {
      expect(() => repo.publishTemplate(''), throwsArgumentError);
      expect(() => repo.unpublishTemplate(''), throwsArgumentError);
    });
  });

  group('listPublishedTemplates', () {
    test('returns only public trainer-templates', () async {
      await seedRoutine(
        'tpl-pub',
        source: 'trainer-template',
        visibility: 'public',
        assignedBy: 'trainer-a',
      );
      await seedRoutine(
        'tpl-priv',
        source: 'trainer-template',
        visibility: 'private',
        assignedBy: 'trainer-a',
      );
      await seedRoutine('sys-pub', source: 'system', visibility: 'public');
      await seedRoutine(
        'user-pub',
        source: 'user-created',
        visibility: 'public',
        createdBy: 'athlete-1',
      );

      final result = await repo.listPublishedTemplates();

      expect(result.map((r) => r.id).toList(), ['tpl-pub']);
    });

    test('deserializes CF-written aggregates from the doc', () async {
      await seedRoutine(
        'tpl-pub',
        source: 'trainer-template',
        visibility: 'public',
        assignedBy: 'trainer-a',
      );
      await firestore
          .collection('routines')
          .doc('tpl-pub')
          .update({'ratingAvg': 4.5, 'ratingsCount': 3});

      final result = await repo.listPublishedTemplates();

      expect(result.single.ratingAvg, 4.5);
      expect(result.single.ratingsCount, 3);
    });
  });

  group('createTemplate (aggregate hygiene)', () {
    test('never writes the CF-only aggregate keys', () async {
      // A Routine instance CAN carry aggregates in memory (e.g. copied from
      // a published template); the wire payload must still omit them or the
      // firestore.rules create guard would deny the write.
      const draft = Routine(
        id: '',
        name: 'Nueva plantilla',
        level: ExperienceLevel.beginner,
        days: [],
        assignedBy: 'trainer-a',
        ratingAvg: 4.9,
        ratingsCount: 99,
      );

      final created = await repo.createTemplate(draft);

      final data =
          (await firestore.collection('routines').doc(created.id).get())
              .data()!;
      expect(data.containsKey('ratingAvg'), isFalse);
      expect(data.containsKey('ratingsCount'), isFalse);
      expect(data['visibility'], 'private');
    });
  });

  group('upsertTemplateRating', () {
    test('writes the rating at the deterministic doc id (rater uid)', () async {
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 5, comment: 'Excelente'),
      );

      final data = (await firestore
              .collection('routines')
              .doc('tpl-1')
              .collection('ratings')
              .doc('user-1')
              .get())
          .data()!;
      expect(data['userId'], 'user-1');
      expect(data['rating'], 5);
      expect(data['comment'], 'Excelente');
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
    });

    test('second upsert fully replaces the doc (set without merge)', () async {
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 5, comment: 'Excelente'),
      );
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 2),
      );

      final data = (await firestore
              .collection('routines')
              .doc('tpl-1')
              .collection('ratings')
              .doc('user-1')
              .get())
          .data()!;
      expect(data['rating'], 2);
      // Stale comment must not survive the overwrite.
      expect(data['comment'], isNull);
    });

    test('an edit preserves the ORIGINAL createdAt', () async {
      // The rules pin createdAt to its stored value on update, so a caller
      // that stamps both timestamps with "now" must still pass. Without
      // this preservation the edit would be permission-denied in prod.
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 5, createdMs: 1000),
      );
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 2, createdMs: 9000),
      );

      final data = (await firestore
              .collection('routines')
              .doc('tpl-1')
              .collection('ratings')
              .doc('user-1')
              .get())
          .data()!;
      expect(data['rating'], 2);
      expect(
        (data['createdAt']! as Timestamp).millisecondsSinceEpoch,
        1000,
      );
      expect(
        (data['updatedAt']! as Timestamp).millisecondsSinceEpoch,
        9000,
      );
    });

    test('rejects out-of-range ratings and oversized comments', () {
      expect(
        () => repo.upsertTemplateRating(
          routineId: 'tpl-1',
          rating: makeRating('user-1', rating: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTemplateRating(
          routineId: 'tpl-1',
          rating: makeRating('user-1', rating: 6),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTemplateRating(
          routineId: 'tpl-1',
          rating: makeRating('user-1', comment: 'x' * 501),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTemplateRating(
          routineId: '',
          rating: makeRating('user-1'),
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.upsertTemplateRating(
          routineId: 'tpl-1',
          rating: makeRating(''),
        ),
        throwsArgumentError,
      );
    });

    test('a 500-char comment is accepted (boundary)', () async {
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', comment: 'x' * 500),
      );

      final snap = await firestore
          .collection('routines')
          .doc('tpl-1')
          .collection('ratings')
          .doc('user-1')
          .get();
      expect(snap.exists, isTrue);
    });
  });

  group('watchTemplateRatings', () {
    test('emits ratings newest-first with userId injected from the doc id',
        () async {
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-old', createdMs: 1000),
      );
      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-new', createdMs: 2000),
      );
      // A doc whose body lost its userId — the doc id must win.
      await firestore
          .collection('routines')
          .doc('tpl-1')
          .collection('ratings')
          .doc('user-legacy')
          .set({
        'rating': 3,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(3000),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(3000),
      });

      final ratings = await repo.watchTemplateRatings('tpl-1').first;

      expect(
        ratings.map((r) => r.userId).toList(),
        ['user-legacy', 'user-new', 'user-old'],
      );
    });

    test('caps the stream at the requested limit', () async {
      for (var i = 0; i < 5; i++) {
        await repo.upsertTemplateRating(
          routineId: 'tpl-1',
          rating: makeRating('user-$i', createdMs: 1000 + i),
        );
      }

      final ratings = await repo.watchTemplateRatings('tpl-1', limit: 2).first;

      expect(ratings.map((r) => r.userId).toList(), ['user-4', 'user-3']);
    });
  });

  group('assignTemplateToAthlete', () {
    test('drops the community aggregates from the assigned copy', () async {
      const template = Routine(
        id: 'tpl-1',
        name: 'Plantilla publicada',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerTemplate,
        assignedBy: 'trainer-a',
        visibility: RoutineVisibility.public,
        ratingAvg: 4.5,
        ratingsCount: 3,
      );

      final assigned = await repo.assignTemplateToAthlete(
        template: template,
        athleteId: 'athlete-1',
      );

      // The returned object must match the persisted doc — a published
      // template's reputation does not follow its private copies.
      expect(assigned.ratingAvg, isNull);
      expect(assigned.ratingsCount, isNull);
      expect(assigned.visibility, RoutineVisibility.private);

      final data =
          (await firestore.collection('routines').doc(assigned.id).get())
              .data()!;
      expect(data.containsKey('ratingAvg'), isFalse);
      expect(data.containsKey('ratingsCount'), isFalse);
    });
  });

  group('watchMyTemplateRating', () {
    test('emits null while absent, then the rating after an upsert', () async {
      final before = await repo
          .watchMyTemplateRating(routineId: 'tpl-1', userId: 'user-1')
          .first;
      expect(before, isNull);

      await repo.upsertTemplateRating(
        routineId: 'tpl-1',
        rating: makeRating('user-1', rating: 4, comment: 'Buena'),
      );

      final after = await repo
          .watchMyTemplateRating(routineId: 'tpl-1', userId: 'user-1')
          .first;
      expect(after, isNotNull);
      expect(after!.rating, 4);
      expect(after.comment, 'Buena');
      expect(after.userId, 'user-1');
    });
  });
}
