// #1498 — `watchById` es la versión EN VIVO de `getById`: la vista previa del
// PF la usa para ver su propio guardado sin reiniciar la app.

import 'package:cloud_firestore/cloud_firestore.dart' show SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/trainer_public_profile_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainerPublicProfileRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = TrainerPublicProfileRepository(firestore: firestore);
  });

  test('emite el perfil actual y cada cambio posterior del documento',
      () async {
    final doc = firestore.collection('trainerPublicProfiles').doc('pf-1');
    await doc.set({'uid': 'pf-1', 'displayName': 'Coach Ana'});

    final emitidos = <int?>[];
    final sub = repo.watchById('pf-1').listen(
          (p) => emitidos.add(p?.trainerExperienceYears),
        );
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    await doc.set({'trainerExperienceYears': 8}, SetOptions(merge: true));
    await Future<void>.delayed(Duration.zero);

    expect(emitidos, [null, 8]);
  });

  test('un documento que no existe emite null', () async {
    final primero = await repo.watchById('no-existe').first;

    expect(primero, isNull);
  });

  test('no repite el mismo perfil: sólo cambia la metadata, no los datos',
      () async {
    final doc = firestore.collection('trainerPublicProfiles').doc('pf-1');
    await doc.set({'uid': 'pf-1', 'displayName': 'Coach Ana'});

    var emisiones = 0;
    final sub = repo.watchById('pf-1').listen((_) => emisiones++);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);

    // Re-escribir lo mismo no cambia los datos.
    await doc.set({'displayName': 'Coach Ana'}, SetOptions(merge: true));
    await Future<void>.delayed(Duration.zero);

    expect(emisiones, 1);
  });
}
