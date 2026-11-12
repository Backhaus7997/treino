// Vínculos PF↔alumno para los tests que sólo necesitan su ESTADO (#1695).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

TrainerLink linkDe(
  String athleteId, {
  String trainerId = 'trainer-1',
  TrainerLinkStatus status = TrainerLinkStatus.active,
}) =>
    TrainerLink(
      id: 'link-$athleteId-${status.name}',
      trainerId: trainerId,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026),
    );

/// Un [TrainerLinkRepository] REAL sobre un Firestore falso con [links]
/// sembrados: lo que prueba la verificación previa a escribir es la lectura de
/// verdad, no un mock que contesta lo que el test quiere.
Future<TrainerLinkRepository> repoConVinculos(List<TrainerLink> links) async {
  final firestore = FakeFirebaseFirestore();
  for (final l in links) {
    await firestore.collection('trainer_links').doc(l.id).set(l.toJson());
  }
  return TrainerLinkRepository(firestore: firestore);
}
