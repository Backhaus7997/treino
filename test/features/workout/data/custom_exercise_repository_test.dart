import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/data/custom_exercise_video_upload_service.dart';

// [#553] Mis ejercicios ordenaba case-sensitive: `orderBy('name')` usa byte
// order UTF-8, así que "Pantorrilla en prensa" (P=80) saltaba ANTES de
// "abdominales cortitos" (a=97). El repo ahora ordena en Dart por foldSearch
// (case+tildes, el mismo normalizador de la búsqueda de #209) y deriva
// `nameLowercase` en cada write — los callers nunca lo pasan.

class _MockVideoUploadService extends Mock
    implements CustomExerciseVideoUploadService {}

void main() {
  late FakeFirebaseFirestore firestore;
  late CustomExerciseRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CustomExerciseRepository(
      firestore: firestore,
      videoUploadService: _MockVideoUploadService(),
    );
  });

  group('watchForTrainer — orden alfabético insensible (#553)', () {
    test(
        'la mayúscula inicial no salta al principio: el orden observado del '
        'issue queda alfabético', () async {
      // El orden EXACTO reportado en #553, sembrado desordenado a propósito.
      const names = [
        'Pantorrilla en prensa',
        'abdominales en v',
        'dorsiflexion con kettble',
        'abdominales cortitos con disco',
        'chinito con rotacion de torax',
        'biceps a press de hombro con mancuerna',
        'abdominales oblicuas',
        'correctivos obeliscos',
      ];
      for (final n in names) {
        await repo.create(trainerId: 't1', name: n);
      }

      final result = await repo.watchForTrainer('t1').first;

      expect(result.map((e) => e.name).toList(), [
        'abdominales cortitos con disco',
        'abdominales en v',
        'abdominales oblicuas',
        'biceps a press de hombro con mancuerna',
        'chinito con rotacion de torax',
        'correctivos obeliscos',
        'dorsiflexion con kettble',
        'Pantorrilla en prensa',
      ]);
    });

    test('las tildes no desplazan: "Índice" ordena junto a "i", no al final',
        () async {
      for (final n in [
        'zancadas',
        'Índice de rotación',
        'isquios en camilla'
      ]) {
        await repo.create(trainerId: 't1', name: n);
      }

      final result = await repo.watchForTrainer('t1').first;

      expect(result.map((e) => e.name).toList(), [
        'Índice de rotación',
        'isquios en camilla',
        'zancadas',
      ]);
    });

    test(
        'docs pre-#553 (sin nameLowercase) ordenan igual que los nuevos — '
        'nadie desaparece de la lista', () async {
      // Doc legacy escrito antes del fix: sin nameLowercase. Un
      // orderBy('nameLowercase') server-side lo EXCLUIRÍA del stream hasta
      // correr el backfill; el sort en Dart no.
      await firestore
          .collection('users')
          .doc('t1')
          .collection('customExercises')
          .add({
        'ownerId': 't1',
        'name': 'Pantorrilla en prensa',
        'muscleGroup': '',
        'description': '',
        'createdAt': DateTime.utc(2026, 1, 1),
        'updatedAt': DateTime.utc(2026, 1, 1),
      });
      await repo.create(trainerId: 't1', name: 'abdominales en v');

      final result = await repo.watchForTrainer('t1').first;

      expect(result.map((e) => e.name).toList(), [
        'abdominales en v',
        'Pantorrilla en prensa',
      ]);
    });
  });

  group('nameLowercase derivado en el write path (#553)', () {
    test('create escribe nameLowercase normalizado (case + tildes)', () async {
      final created = await repo.create(
        trainerId: 't1',
        name: 'Elevación Lateral',
      );

      final doc = await firestore
          .collection('users')
          .doc('t1')
          .collection('customExercises')
          .doc(created.id)
          .get();

      expect(doc.data()!['nameLowercase'], 'elevacion lateral');
    });

    test('update re-deriva nameLowercase al renombrar', () async {
      final created = await repo.create(trainerId: 't1', name: 'burpees');

      await repo.update(created.copyWith(name: 'Búlgaras con mancuerna'));

      final doc = await firestore
          .collection('users')
          .doc('t1')
          .collection('customExercises')
          .doc(created.id)
          .get();

      expect(doc.data()!['nameLowercase'], 'bulgaras con mancuerna');
      expect(doc.data()!['name'], 'Búlgaras con mancuerna');
    });
  });
}
