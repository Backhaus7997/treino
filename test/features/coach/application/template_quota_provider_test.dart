// template_quota_provider_test.dart — el gate de UX cruza DOS fuentes (el
// tope del servidor y el conteo en vivo) y tiene que distinguir "todavía no
// sé" de "no hay tope", y filtrar las archivadas del conteo.
//
// El eje de este archivo es el mismo que
// `custom_exercise_quota_provider_test.dart`: una fuente que no resolvió NO
// es una fuente que dijo "no hay tope".

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider, trainerTemplatesStreamProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

const _uid = 'trainer-1';

Routine _plantilla(String id) => Routine(
      id: id,
      name: 'Plantilla $id',
      level: ExperienceLevel.beginner,
      days: const [],
      assignedBy: _uid,
    );

/// Container con `users/{_uid}` sembrado (con o sin `planLimits`) y N
/// plantillas ya creadas vía el repositorio real, [archivadas] de ellas
/// archivadas — así el conteo pasa por el mismo `watchTemplatesBy` que usa
/// la grilla del Hub y la sección de plantillas del móvil.
Future<ProviderContainer> _containerWith({
  Map<String, Object?>? planLimits,
  bool seedUserDoc = true,
  int templatesCount = 0,
  int archivadas = 0,
  String? uid = _uid,
}) async {
  final firestore = FakeFirebaseFirestore();
  if (seedUserDoc) {
    await firestore.collection('users').doc(_uid).set({
      'uid': _uid,
      if (planLimits != null) 'planLimits': planLimits,
    });
  }

  final repo = RoutineRepository(firestore: firestore);
  for (var i = 0; i < templatesCount; i++) {
    final creada = await repo.createTemplate(_plantilla('t$i'));
    if (i < archivadas) {
      await repo.archive(creada.id);
    }
  }

  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(uid),
      routineRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Deja asentar los DOS streams (el doc de `users/{uid}` y la colección de
/// plantillas) antes de leer.
Future<AsyncValue<TemplateQuota>> _settle(ProviderContainer container) async {
  final sub = container.listen(templateQuotaProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return sub.read();
}

void main() {
  group('templateQuotaProvider', () {
    test('planLimits ausente ⇒ limit null (sin tope), cuenta igual', () async {
      final c = await _containerWith(templatesCount: 2);
      final result = await _settle(c);

      expect(result.hasValue, isTrue);
      expect(result.valueOrNull, (limit: null, count: 2));
    });

    test('planLimits.templates == null ⇒ sin tope', () async {
      final c = await _containerWith(
        planLimits: {'templates': null},
        templatesCount: 2,
      );
      final result = await _settle(c);

      expect(result.valueOrNull!.limit, isNull);
      expect(result.valueOrNull!.count, 2);
    });

    test('planLimits.templates numérico ⇒ tope + conteo del stream',
        () async {
      final c = await _containerWith(
        planLimits: {'templates': 3},
        templatesCount: 2,
      );
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: 3, count: 2));
      expect(result.valueOrNull!.isAtOrOverLimit, isFalse);
    });

    test('el borde: count < limit al crear, count == limit YA bloquea',
        () async {
      final c = await _containerWith(
        planLimits: {'templates': 3},
        templatesCount: 3,
      );
      final result = await _settle(c);

      expect(result.valueOrNull!.isAtOrOverLimit, isTrue);
    });

    test('por encima del tope (bajó de plan) también bloquea, no borra',
        () async {
      final c = await _containerWith(
        planLimits: {'templates': 3},
        templatesCount: 5,
      );
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: 3, count: 5));
      expect(result.valueOrNull!.isAtOrOverLimit, isTrue);
    });

    // El punto del provider (docs/limite-plantillas-pf.md §2): cuentan las
    // publicadas, NO las archivadas.
    test('las archivadas NO cuentan para el tope', () async {
      final c = await _containerWith(
        planLimits: {'templates': 3},
        templatesCount: 5,
        archivadas: 3,
      );
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: 3, count: 2));
      expect(result.valueOrNull!.isAtOrOverLimit, isFalse);
    });

    test('sin uid ⇒ dato inmediato, limit null y count 0', () async {
      final c = await _containerWith(uid: null);
      final result = await _settle(c);

      expect(result.valueOrNull, (limit: null, count: 0));
    });

    test(
        'caché fría / conteo en vuelo: mientras UNA fuente no resolvió, sigue '
        'en AsyncLoading — no colapsa a un conteo optimista de 0', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(_uid).set({
        'uid': _uid,
        'planLimits': {'templates': 3},
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(_uid),
          // Nunca completa: modela el conteo todavía en vuelo.
          trainerTemplatesStreamProvider.overrideWith(
            (ref, trainerId) => Completer<List<Routine>>().future.asStream(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(templateQuotaProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(sub.read().isLoading, isTrue);
      expect(sub.read().hasValue, isFalse);
    });
  });
}
