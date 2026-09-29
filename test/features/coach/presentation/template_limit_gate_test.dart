// template_limit_gate_test.dart — el embudo único de "crear o restaurar una
// plantilla" (docs/limite-plantillas-pf.md PR3).
//
// Dos ejes se prueban acá:
//   1. El alumno NUNCA se bloquea, pase lo que pase con la cuota — se corta
//      por rol antes de mirar el número.
//   2. Bajo/en/sobre el tope, con el mismo borde que ejercicios propios:
//      `count == limit` YA bloquea (no hace falta pasarse).
//
// Y que la anotación (`registrarTopeDelPlanPf`) se dispare sólo cuando
// corresponde, con el `kind` correcto — es lo que el mail del PR4 necesita
// para saber a quién escribirle y por qué.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach/presentation/template_limit_gate.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class _RepoFalso extends Mock implements UserRepository {}

const _uid = 'u1';

UserProfile _profile(UserRole role, {TrainerSubscription? subscription}) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    uid: _uid,
    email: 'a@b.com',
    displayName: null,
    role: role,
    createdAt: now,
    updatedAt: now,
    subscription: subscription,
  );
}

/// Monta un botón que corre [intentarCrearPlantilla] (o, con [rebote],
/// [mostrarAvisoTopeDePlantillasPorRebote]) y devuelve lo que resolvió.
///
/// `null` = todavía no resolvió: el rebote espera a que se cierre el aviso,
/// así que con el aviso abierto no hay resultado.
///
/// [subscription] es el tier NOMINAL del PF (lo que pagó) — default `null`
/// (Free, sin backfill). Sirve para el Cambio 2 (P1): probar que el aviso
/// nombra el tier EFECTIVO (el que explica `quota.limit`), no éste a ciegas.
Future<bool?> _correr(
  WidgetTester tester, {
  required UserRole role,
  required AsyncValue<TemplateQuota> quota,
  required UserRepository repo,
  String? uid = _uid,
  bool rebote = false,
  TrainerSubscription? subscription,
}) async {
  bool? resultado;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_profile(role, subscription: subscription)),
        ),
        templateQuotaProvider.overrideWithValue(quota),
        currentUidProvider.overrideWithValue(uid),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        // El bloqueo real ahora abre el aviso visual
        // (`showTrainerLimitNotice`), y la forma móvil usa `AppL10n` — sin
        // delegates acá el `build` del sheet revienta con "Null check
        // operator used on a null value" apenas este test corre junto a
        // otros (Localizations sin resolver).
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
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
                  resultado = rebote
                      ? await mostrarAvisoTopeDePlantillasPorRebote(
                          context, ref)
                      : await intentarCrearPlantilla(context, ref);
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

  return resultado;
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  group('intentarCrearPlantilla — el alumno nunca se bloquea', () {
    testWidgets(
        'alumno con cuota EN el tope (si fuera PF) igual puede crear, y no '
        'anota nada', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.athlete,
        quota: const AsyncValue.data((limit: 3, count: 3)),
        repo: repo,
      );

      expect(ok, isTrue);
      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });
  });

  group('intentarCrearPlantilla — PF bajo el tope', () {
    testWidgets('count < limit ⇒ puede crear, sin anotar', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 3, count: 2)),
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

  group('intentarCrearPlantilla — PF en o sobre el tope', () {
    testWidgets('count == limit YA bloquea, y anota el kind correcto',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 3, count: 3)),
        repo: repo,
      );

      expect(ok, isFalse);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindTemplates,
          )).called(1);
    });

    testWidgets('sobre el tope (bajó de plan) también bloquea la creación',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 3, count: 5)),
        repo: repo,
      );

      expect(ok, isFalse);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindTemplates,
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
        quota: const AsyncValue.data((limit: 3, count: 3)),
        repo: repo,
      );

      expect(ok, isFalse);
    });
  });

  group('mostrarAvisoTopeDePlantillasPorRebote — el servidor rechazó', () {
    testWidgets(
        '⚠️ el PF rebotado queda anotado para el mail, como en el embudo',
        (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final mostro = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 3, count: 3)),
        repo: repo,
        rebote: true,
      );

      // El aviso quedó abierto: el rebote todavía lo está esperando.
      expect(mostro, isNull);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindTemplates,
          )).called(1);
    });

    testWidgets(
        '⚠️ con la cuota local cargando, anota igual (el servidor ya decidió) '
        'y cae al error genérico', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final mostro = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.loading(),
        repo: repo,
        rebote: true,
      );

      expect(mostro, isFalse);
      verify(() => repo.registrarTopeDelPlanPf(
            _uid,
            kTrainerLimitHitKindTemplates,
          )).called(1);
    });

    testWidgets('un alumno rebotado no se anota', (tester) async {
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      await _correr(
        tester,
        role: UserRole.athlete,
        quota: const AsyncValue.data((limit: null, count: 3)),
        repo: repo,
        rebote: true,
      );

      verifyNever(() => repo.registrarTopeDelPlanPf(any(), any()));
    });
  });

  group('intentarCrearPlantilla — fail-open mientras carga', () {
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

  group(
      'intentarCrearPlantilla — Cambio 2 (P1): el aviso nombra el tier '
      'EFECTIVO, no el nominal a ciegas', () {
    testWidgets(
        'el caso del hallazgo: Plan 1 no activo, limit del servidor ya es '
        'el de Free (3) ⇒ el aviso dice Free e inactiva, no Plan 1',
        (tester) async {
      // Plan 1 nominal NO tiene tope de plantillas (kTierTemplateLimits[
      // plan1] es null) — que el gate haya bloqueado con limit=3 SÓLO puede
      // explicarse si el efectivo cayó a Free. Antes de este cambio el aviso
      // decía «Plan 1 incluye…», que no es cierto en ningún mundo.
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.paused,
        ),
        quota: const AsyncValue.data((limit: 3, count: 3)),
        repo: repo,
      );

      expect(ok, isFalse);
      expect(
        find.textContaining('Tu suscripción a Plan 1 no está activa'),
        findsOneWidget,
      );
      expect(find.textContaining('Tu plan Plan 1 incluye'), findsNothing);
      // Sin upsell: no se le ofrece "el siguiente" a quien ya pagó Plan 1.
      expect(find.text('PLAN 2'), findsNothing);
    });

    testWidgets(
        'límite de plantillas que no es el de ningún tier (ajustado a mano) '
        '⇒ cuerpo genérico, sin nombrar un plan', (tester) async {
      // Sólo Free tiene tope de plantillas (kTierTemplateLimits): un limit
      // finito que no sea 3 no puede explicarse por ningún tier conocido.
      final repo = _RepoFalso();
      when(() => repo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      final ok = await _correr(
        tester,
        role: UserRole.trainer,
        quota: const AsyncValue.data((limit: 10, count: 10)),
        repo: repo,
      );

      expect(ok, isFalse);
      expect(
        find.text('Tu plan incluye 10 plantillas. Podés editar o archivar '
            'las que ya tenés.'),
        findsOneWidget,
      );
      expect(find.textContaining('Free incluye'), findsNothing);
      expect(find.text('PLAN 1'), findsNothing);
    });
  });
}
