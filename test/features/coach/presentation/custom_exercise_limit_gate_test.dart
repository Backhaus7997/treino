// custom_exercise_limit_gate_test.dart — el embudo único de "crear ejercicio
// propio" (docs/limite-ejercicios-pf.md PR3).
//
// Dos ejes se prueban acá:
//   1. El alumno NUNCA se bloquea, pase lo que pase con la cuota — se corta
//      por rol antes de mirar el número.
//   2. Bajo/en/sobre el tope, con el borde de E6: `count == limit` YA
//      bloquea (no hace falta pasarse).
//
// Y que la anotación (`registrarTopeDelPlanPf`) se dispare sólo cuando
// corresponde, con el `kind` correcto — es lo que el mail del PR4 necesita
// para saber a quién escribirle y por qué.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/presentation/custom_exercise_limit_gate.dart';
import 'package:treino/features/coach/presentation/custom_exercise_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';

class _RepoFalso extends Mock implements UserRepository {}

const _uid = 'u1';

UserProfile _profile(UserRole role) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    uid: _uid,
    email: 'a@b.com',
    displayName: null,
    role: role,
    createdAt: now,
    updatedAt: now,
  );
}

/// Monta un botón que corre [intentarCrearEjercicioPropio] y devuelve lo que
/// resolvió.
Future<bool> _correr(
  WidgetTester tester, {
  required UserRole role,
  required AsyncValue<CustomExerciseQuota> quota,
  required UserRepository repo,
  String? uid = _uid,
}) async {
  bool? resultado;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => Stream.value(_profile(role))),
        customExerciseQuotaProvider.overrideWithValue(quota),
        currentUidProvider.overrideWithValue(uid),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // `watch` fuerza la suscripción temprana al stream para que ya
              // esté resuelto cuando el tap llame a `ref.read` adentro del
              // embudo — un `ref.read` suelto en el primer frame no alcanza
              // a esperar la emisión async de `Stream.value`.
              ref.watch(userProfileProvider);
              return ElevatedButton(
                onPressed: () async {
                  resultado = await intentarCrearEjercicioPropio(
                    context,
                    ref,
                  );
                },
                child: const Text('crear'),
              );
            },
          ),
        ),
      ),
    ),
  );
  // Deja asentar la emisión async del stream de perfil.
  await tester.pump();

  await tester.tap(find.text('crear'));
  await tester.pumpAndSettle();

  return resultado!;
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  group('intentarCrearEjercicioPropio — el alumno nunca se bloquea', () {
    testWidgets(
        'alumno con cuota EN el tope (si fuera PF) igual puede crear, y no '
        'anota nada', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.athlete,
        quota: const AsyncValue.data((limit: 20, count: 20)),
        repo: repo,
      );

      expect(ok, isTrue);
      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });
  });

  group('intentarCrearEjercicioPropio — PF bajo el tope', () {
    testWidgets('count < limit ⇒ puede crear, sin anotar', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 20, count: 19)),
        repo: repo,
      );

      expect(ok, isTrue);
      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });

    testWidgets('sin tope (limit null) ⇒ puede crear con cualquier conteo',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: null, count: 999)),
        repo: repo,
      );

      expect(ok, isTrue);
      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });
  });

  group('intentarCrearEjercicioPropio — PF en o sobre el tope', () {
    testWidgets('E6 — count == limit YA bloquea, y anota el kind correcto',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 20, count: 20)),
        repo: repo,
      );

      expect(ok, isFalse);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindCustomExercises,
          )).called(1);
    });

    testWidgets('E3 — sobre el tope (bajó de plan) también bloquea la creación',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 20, count: 25)),
        repo: repo,
      );

      expect(ok, isFalse);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindCustomExercises,
          )).called(1);
    });

    testWidgets('⚠️ si la anotación falla, el gate igual bloquea sin tirar',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenThrow(Exception('firestore caído'));

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 20, count: 20)),
        repo: repo,
      );

      expect(ok, isFalse);
    });
  });

  group('intentarCrearEjercicioPropio — fail-open mientras carga', () {
    testWidgets('cuota en AsyncLoading ⇒ no bloquea (el servidor manda)',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.loading(),
        repo: repo,
      );

      expect(ok, isTrue);
      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });
  });
}
