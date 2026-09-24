// custom_exercise_quota_provider_test.dart — el gate de UX cruza DOS fuentes
// (el tope del servidor y el conteo en vivo) y tiene que distinguir "todavía
// no sé" de "no hay tope".
//
// El eje de este archivo es el mismo que `athleteEntitlementProvider_test`:
// una fuente que no resolvió NO es una fuente que dijo "no hay tope". Colapsar
// los dos —con `valueOrNull` en vez de `hasValue`, por ejemplo— convierte un
// "no sé" en un "no hay" (ver la memoria del repo sobre `AsyncValue<T?>`), y
// acá el costo de esa confusión es mostrarle "sin tope" a un PF con caché
// fría, o "en el tope" con un conteo optimista de cero.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/custom_exercise_providers.dart'
    show
        customExerciseRepositoryProvider,
        customExercisesForTrainerStreamProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/data/custom_exercise_video_upload_service.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';

class _MockVideoUploadService extends Mock
    implements CustomExerciseVideoUploadService {}

const _uid = 'trainer-1';

/// Container con `users/{_uid}` sembrado (con o sin `planLimits`) y N
/// ejercicios propios ya creados vía el repositorio real (no docs a mano:
/// así el conteo pasa por el mismo `watchForTrainer` que usan "Mis
/// ejercicios" y los pickers).
Future<ProviderContainer> _containerWith({
  Map<String, Object?>? planLimits,
  bool seedUserDoc = true,
  int customExercisesCount = 0,
  String? uid = _uid,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (seedUserDoc) {
    await firestore.collection('users').doc(_uid).set({
      'uid': _uid,
      if (planLimits != null) 'planLimits': planLimits,
    });
  }

  final repo = CustomExerciseRepository(
    firestore: firestore,
    videoUploadService: _MockVideoUploadService(),
  );
  for (var i = 0; i < customExercisesCount; i++) {
    await repo.create(trainerId: _uid, name: 'Ejercicio $i');
  }

  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(uid),
      customExerciseRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Deja asentar los DOS streams (el doc de `users/{uid}` y la colección de
/// `customExercises`) antes de leer.
Future<AsyncValue<CustomExerciseQuota>> _settle(
  ProviderContainer container,
) async {
  final sub = container.listen(customExerciseQuotaProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return sub.read();
}

void main() {
  group('customExerciseQuotaProvider', () {
    test('planLimits ausente ⇒ limit null (sin tope), cuenta igual', () async {
      final c = await _containerWith(customExercisesCount: 3);
      final result = await _settle(c);

      expect(result.hasValue, isTrue);
      expect(result.valueOrNull, (limit: null, count: 3));
    });

    test('planLimits.customExercises == null ⇒ sin tope', () async {
      final c = await _containerWith(
        planLimits: {'customExercises': null},
        customExercisesCount: 5,
      );
      final result = await _settle(c);

      expect(result.valueOrNull!.limit, isNull);
      expect(result.valueOrNull!.count, 5);
    });

    test('planLimits.customExercises numérico ⇒ tope + conteo del stream',
        () async {
      final c = await _containerWith(
        planLimits: {'customExercises': 20},
        customExercisesCount: 12,
      );
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: 20, count: 12));
      expect(result.valueOrNull!.isAtOrOverLimit, isFalse);
    });

    test('E6 — el borde es count < limit: count == limit YA bloquea', () async {
      final c = await _containerWith(
        planLimits: {'customExercises': 20},
        customExercisesCount: 20,
      );
      final result = await _settle(c);

      expect(result.valueOrNull!.isAtOrOverLimit, isTrue);
    });

    test('E3 — por encima del tope (bajó de plan) también bloquea, no borra',
        () async {
      final c = await _containerWith(
        planLimits: {'customExercises': 20},
        customExercisesCount: 25,
      );
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: 20, count: 25));
      expect(result.valueOrNull!.isAtOrOverLimit, isTrue);
    });

    test('sin uid ⇒ dato inmediato, limit null y count 0', () async {
      final c = await _containerWith(uid: null);
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: null, count: 0));
    });

    test(
        'caché fría / conteo en vuelo: mientras UNA fuente no resolvió, sigue '
        'en AsyncLoading — no colapsa a un conteo optimista de 0', () async {
      // Mismo eje que "mientras el vínculo no resolvió ⇒ unknown, no free" en
      // athleteEntitlementProvider_test.dart: el stream de customExercises
      // nunca emite (modela el round-trip en vuelo), mientras que el doc de
      // planLimits SÍ resolvió. Si el provider combinado colapsara al primer
      // valor resuelto, un PF en el tope leería `count: 0` y el gate lo
      // dejaría pasar de más.
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(_uid).set({
        'uid': _uid,
        'planLimits': {'customExercises': 20},
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(_uid),
          // Nunca completa: modela el conteo todavía en vuelo.
          customExercisesForTrainerStreamProvider.overrideWith(
            (ref, trainerId) =>
                Completer<List<CustomExercise>>().future.asStream(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(customExerciseQuotaProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(sub.read().isLoading, isTrue);
      expect(sub.read().hasValue, isFalse);
    });
  });
}
