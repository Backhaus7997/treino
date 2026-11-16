// Vínculos PF↔alumno para los tests que sólo necesitan su ESTADO (#1695).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, Override;
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show alumnoConVinculoVivoProvider, trainerLinkRepositoryProvider;
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

/// Doble SINCRÓNICO para los harness que no hablan del vínculo: el servidor
/// tiene vivos a [vivos]. Lo que prueba la verificación de verdad es
/// [repoConVinculos], no esto.
TrainerLinkRepository repoConVivos(Iterable<String> vivos) =>
    _RepoConVivos(vivos.toSet());

class _RepoConVivos extends Fake implements TrainerLinkRepository {
  _RepoConVivos(this._vivos);
  final Set<String> _vivos;

  @override
  Future<Set<String>> alumnosConVinculoVivo(String trainerId) async => _vivos;
}

/// Para los harness que montan una pantalla que CREA un plan para un alumno
/// pero no hablan del vínculo (#1695): cualquier alumno está vivo, tanto en el
/// roster (la puerta de `build`) como en el servidor (la verificación previa a
/// escribir). Va ANTES de los overrides del test, para que éstos le ganen.
List<Override> alumnosVivosOverrides() => [
      alumnoConVinculoVivoProvider
          .overrideWith((ref, athleteId) => const AsyncData(true)),
      trainerLinkRepositoryProvider.overrideWithValue(_RepoTodosVivos()),
    ];

/// El servidor no responde (sin red, permiso): verificar el vínculo TIRA, y
/// quien escribe tiene que tratarlo como «no se sabe», nunca como «vivo».
TrainerLinkRepository repoQueNoResponde() => _RepoQueNoResponde();

class _RepoQueNoResponde extends Fake implements TrainerLinkRepository {
  @override
  Future<bool> tieneVinculoVivo({
    required String trainerId,
    required String athleteId,
  }) async =>
      throw Exception('offline');
}

class _RepoTodosVivos extends Fake implements TrainerLinkRepository {
  @override
  Future<bool> tieneVinculoVivo({
    required String trainerId,
    required String athleteId,
  }) async =>
      true;
}
