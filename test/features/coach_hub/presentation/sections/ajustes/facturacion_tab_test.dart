import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_cancel.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer({TrainerSubscription? subscription}) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      subscription: subscription,
    );

Widget _harness({
  required List<TrainerLink> links,
  UserProfile? profile,
  Stream<CustomExerciseQuota?>? usage,
  Stream<TemplateQuota?>? templateUsage,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(links)),
        customExerciseUsageSummaryProvider.overrideWith(
          (ref) => usage ?? Stream<CustomExerciseQuota?>.value(null),
        ),
        templateUsageSummaryProvider.overrideWith(
          (ref) => templateUsage ?? Stream<TemplateQuota?>.value(null),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: FacturacionTab())),
    );

TrainerLink _link(String athleteId, TrainerLinkStatus status) => TrainerLink(
      id: 'link_$athleteId',
      trainerId: 'pf1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime(2025, 1, 1),
    );

void main() {
  testWidgets('sin suscripción → Free, límite 2, uso 0', (tester) async {
    await tester.pumpWidget(_harness(links: const []));
    await tester.pump();

    expect(find.text('FACTURACIÓN TREINO'), findsOneWidget);
    expect(find.text('TREINO Coach · Free'), findsOneWidget);
    expect(find.text('0 / 2'), findsOneWidget);
    // CAMBIAR PLAN existe pero deshabilitado (pantalla es PR3).
    expect(find.text('CAMBIAR PLAN'), findsOneWidget);
    // Ya NO hay empty state ni historial de comprobantes (fuera de scope).
    expect(find.text('Facturación próximamente'), findsNothing);
    expect(find.text('HISTORIAL DE FACTURACIÓN'), findsNothing);
  });

  testWidgets('carga ponderada: 2 activos + 1 pausado = 2.5 / límite',
      (tester) async {
    await tester.pumpWidget(_harness(
      profile: _trainer(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.active,
          weightLimit: 7,
        ),
      ),
      links: [
        _link('a1', TrainerLinkStatus.active),
        _link('a2', TrainerLinkStatus.active),
        _link('a3', TrainerLinkStatus.paused),
      ],
    ));
    await tester.pump();

    expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
    // 2×1.0 + 1×0.5 = 2.5, límite del Plan 1 = 7.
    expect(find.text('2.5 / 7'), findsOneWidget);
  });

  testWidgets('entero se muestra sin decimal (3 activos → "3 / 7")',
      (tester) async {
    await tester.pumpWidget(_harness(
      profile: _trainer(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.active,
          weightLimit: 7,
        ),
      ),
      links: [
        _link('a1', TrainerLinkStatus.active),
        _link('a2', TrainerLinkStatus.active),
        _link('a3', TrainerLinkStatus.active),
      ],
    ));
    await tester.pump();

    expect(find.text('3 / 7'), findsOneWidget);
  });

  testWidgets('dedup por athleteId (activo duplicado cuenta 1)',
      (tester) async {
    await tester.pumpWidget(_harness(links: [
      _link('a1', TrainerLinkStatus.active),
      _link('a1', TrainerLinkStatus.active),
    ]));
    await tester.pump();

    // Free límite 2, un solo athlete distinto → 1 / 2.
    expect(find.text('1 / 2'), findsOneWidget);
  });

  // ── Línea de uso de ejercicios propios (docs/limite-ejercicios-pf.md §PR5) ──
  group('línea de uso de ejercicios propios', () {
    testWidgets('con tope: "Ejercicios propios: 12 de 60"', (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        usage: Stream.value((limit: 60, count: 12)),
      ));
      await tester.pump();

      expect(find.text('Ejercicios propios: 12 de 60'), findsOneWidget);
    });

    // El interruptor del servidor está apagado hoy para TODOS los planes
    // (no sólo Plan 3): `limit == null` no puede leerse acá como "Plan 3",
    // así que la línea dice la verdad que el servidor sabe — sin tope — en
    // vez de inventar el tope estático de la tabla de precios.
    testWidgets('sin tope (null): "Ejercicios propios: 12 (sin límite)"',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        usage: Stream.value((limit: null, count: 12)),
      ));
      await tester.pump();

      expect(
        find.text('Ejercicios propios: 12 (sin límite)'),
        findsOneWidget,
      );
    });

    // Mientras carga no se inventa un número — la línea entera se oculta.
    testWidgets('cargando: no muestra la línea (ningún número inventado)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        usage: StreamController<CustomExerciseQuota?>().stream,
      ));
      await tester.pump();

      expect(find.textContaining('Ejercicios propios'), findsNothing);
    });

    // Mismo criterio que "cargando": un error tampoco es un dato confirmado.
    testWidgets('error del provider: no muestra la línea', (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        usage: Stream.error(Exception('boom')),
      ));
      await tester.pump();

      expect(find.textContaining('Ejercicios propios'), findsNothing);
    });

    // El contador todavía no existe en el documento (functions sin deployar,
    // o un PF sin recontar): el provider dice «no sé» y la línea no aparece.
    // Un «0» afirmaría un conteo que nadie hizo.
    testWidgets('contador ausente: no muestra la línea (nunca un 0 inventado)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        usage: Stream<CustomExerciseQuota?>.value(null),
      ));
      await tester.pump();

      expect(find.textContaining('Ejercicios propios'), findsNothing);
    });
  });

  // ── Línea de uso de plantillas (docs/limite-plantillas-pf.md §3 PR5) ──
  group('línea de uso de plantillas', () {
    testWidgets('en Free, con tope: "Plantillas: 2 de 3"', (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        templateUsage: Stream.value((limit: 3, count: 2)),
      ));
      await tester.pump();

      expect(find.text('Plantillas: 2 de 3'), findsOneWidget);
    });

    testWidgets('en Free, sin tope (interruptor apagado): "(sin límite)"',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        templateUsage: Stream.value((limit: null, count: 2)),
      ));
      await tester.pump();

      expect(find.text('Plantillas: 2 (sin límite)'), findsOneWidget);
    });

    // El check central de §6 PR5: sólo en Free. Un PF pago no tiene tope de
    // plantillas — la línea no aporta nada ahí y se omite, aunque el
    // provider tenga datos.
    testWidgets('⚠️ en un plan pago NO se muestra, aunque haya datos',
        (tester) async {
      await tester.pumpWidget(_harness(
        profile: _trainer(
          subscription: const TrainerSubscription(
            tier: SubscriptionTier.plan1,
            status: SubscriptionStatus.active,
            weightLimit: 7,
          ),
        ),
        links: const [],
        templateUsage: Stream.value((limit: 3, count: 2)),
      ));
      await tester.pump();

      expect(find.textContaining('Plantillas'), findsNothing);
    });

    testWidgets('cargando: no muestra la línea (ningún número inventado)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        templateUsage: StreamController<TemplateQuota?>().stream,
      ));
      await tester.pump();

      expect(find.textContaining('Plantillas'), findsNothing);
    });

    testWidgets('contador ausente: no muestra la línea (nunca un 0 inventado)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        templateUsage: Stream<TemplateQuota?>.value(null),
      ));
      await tester.pump();

      expect(find.textContaining('Plantillas'), findsNothing);
    });
  });

  // ── Plan dado de baja ──
  //
  // «Dar de baja la suscripción» sólo aparece en web (`resolvePlanCancel`), así
  // que cada test que quiere VER el link fija esa superficie. Sin eso, los
  // `findsNothing` de abajo pasarían por la plataforma y no por la baja.
  group('plan dado de baja', () {
    // 1/10/2026 12:00, LOCAL (`AppClock.freeze` lo exige).
    setUp(() {
      AppClock.freeze(DateTime(2026, 10, 1, 12));
      debugPlanCancel = planCancelFor(isWeb: true);
    });
    tearDown(() {
      AppClock.unfreeze();
      debugPlanCancel = null;
    });

    /// `weightLimit` es el campo del doc, que el servidor no escribe (ver
    /// [TrainerSubscription]). El fixture lo trae igual porque, mientras la
    /// baja no venza, la card lo prefiere a la tabla. Por default es el de la
    /// tabla de Plan 1; cada test que quiere distinguir «lo que dice el doc» de
    /// «lo que dice la tabla» pasa uno distinto.
    UserProfile pf({
      SubscriptionStatus status = SubscriptionStatus.active,
      SubscriptionTier tier = SubscriptionTier.plan1,
      int? weightLimit = 7,
      DateTime? fin,
    }) =>
        _trainer(
          subscription: TrainerSubscription(
            tier: tier,
            status: status,
            weightLimit: weightLimit,
            currentPeriodEnd: fin,
          ),
        );

    final linkDeBaja = find.text('Dar de baja la suscripción');
    // La línea de la baja: «Plan dado de baja. Sigue activo hasta el d/m.»
    final lineaDeBaja = find.textContaining('Plan dado de baja');

    // Control positivo de todos los `findsNothing` de este grupo: con el plan
    // activo, en web, el link ESTÁ. Si esto fallara, los otros no probarían nada.
    testWidgets('plan activo: ofrece dar de baja y no dice nada de una baja',
        (tester) async {
      await tester.pumpWidget(_harness(links: const [], profile: pf()));
      await tester.pump();

      expect(linkDeBaja, findsOneWidget);
      expect(lineaDeBaja, findsNothing);
    });

    // Pidió la baja y le quedan días: el plan sigue rigiendo y la card tiene
    // que decir las dos cosas. Ya no hay nada que dar de baja.
    testWidgets(
        'baja con días pagos: dice hasta cuándo y NO ofrece dar de baja',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        profile: pf(
          status: SubscriptionStatus.cancelled,
          fin: DateTime.utc(2026, 10, 15, 15),
        ),
      ));
      await tester.pump();

      expect(
        find.text('Plan dado de baja. Sigue activo hasta el 15/10.'),
        findsOneWidget,
      );
      // El plan sigue siendo el que rige.
      expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
      expect(linkDeBaja, findsNothing);
      // Y la palabra vieja no volvió: la tab dice «dado de baja», como su link.
      expect(find.textContaining('Cancelado'), findsNothing);
    });

    // La fecha se lee en ART: 01:30 UTC del 16 son las 22:30 del 15.
    testWidgets('la fecha se lee en calendario argentino, no en UTC',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        profile: pf(
          status: SubscriptionStatus.cancelled,
          fin: DateTime.utc(2026, 10, 16, 1, 30),
        ),
      ));
      await tester.pump();

      expect(
        find.text('Plan dado de baja. Sigue activo hasta el 15/10.'),
        findsOneWidget,
      );
      expect(find.textContaining('16/10'), findsNothing);
    });

    // Vencida no hay «sigue activo hasta»: la línea sería falsa. Y la baja
    // sigue pedida, así que tampoco hay nada que dar de baja.
    testWidgets('baja vencida: sin línea y sin dar de baja', (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        profile: pf(
          status: SubscriptionStatus.cancelled,
          fin: DateTime.utc(2026, 9, 30, 15),
        ),
      ));
      await tester.pump();

      expect(lineaDeBaja, findsNothing);
      expect(find.textContaining('Sigue activo hasta'), findsNothing);
      expect(linkDeBaja, findsNothing);
      // Lo que SÍ dice: el plan que rige, que ya es Free (grupo de abajo).
      expect(find.text('TREINO Coach · Free'), findsOneWidget);
    });

    testWidgets('baja sin fecha de fin: sin línea y sin dar de baja',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: const [],
        profile: pf(status: SubscriptionStatus.cancelled),
      ));
      await tester.pump();

      expect(lineaDeBaja, findsNothing);
      expect(linkDeBaja, findsNothing);
      expect(find.text('TREINO Coach · Free'), findsOneWidget);
    });

    // ── El plan que la card muestra es el que RIGE, no el del doc ──
    //
    // El servidor nunca reescribe el tier cuando una baja vence: el doc sigue
    // diciendo `plan1` para siempre. Antes la card leía eso a secas y decía
    // «Plan 1», «x / 7» (el tope de Plan 1) y ninguna línea de plantillas
    // mientras la pricing page ya marcaba a Free como el actual. Los tests de
    // arriba sólo miran AUSENCIAS (sin línea, sin link); acá va el texto
    // positivo.
    group('plan que rige', () {
      final vencida = DateTime.utc(2026, 9, 30, 15);
      final conDiasPagos = DateTime.utc(2026, 10, 15, 15);

      // El doc del fixture trae `weightLimit: 7`, el tope del plan viejo; nada
      // de lo que se ve puede salir de ahí una vez que la baja venció.
      testWidgets(
          'baja vencida: la card dice Free, con el tope de Free y su línea de '
          'plantillas', (tester) async {
        await tester.pumpWidget(_harness(
          links: [_link('a1', TrainerLinkStatus.active)],
          templateUsage: Stream.value((limit: 3, count: 2)),
          profile: pf(status: SubscriptionStatus.cancelled, fin: vencida),
        ));
        await tester.pump();

        expect(find.text('TREINO Coach · Free'), findsOneWidget);
        expect(find.text('TREINO Coach · Plan 1'), findsNothing);
        // Tope de Free (2), no el 7 del doc: es el del plan que ya no rige.
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.textContaining('/ 7'), findsNothing);
        // Free tiene tope de plantillas, así que la línea aparece. Con el tier
        // del doc (Plan 1, sin tope) no aparecía.
        expect(find.text('Plantillas: 2 de 3'), findsOneWidget);
      });

      testWidgets('baja sin fecha de fin: lo mismo, es Free', (tester) async {
        await tester.pumpWidget(_harness(
          links: [_link('a1', TrainerLinkStatus.active)],
          templateUsage: Stream.value((limit: 3, count: 2)),
          profile: pf(status: SubscriptionStatus.cancelled),
        ));
        await tester.pump();

        expect(find.text('TREINO Coach · Free'), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.text('Plantillas: 2 de 3'), findsOneWidget);
      });

      // Un Plan 3 sin `weightLimit` en el doc: su tier no tiene tope. Vencida
      // la baja, ese «sin tope» no puede sobrevivir: el que rige es el de Free.
      testWidgets(
          'baja vencida de un Plan 3: el tope es el de Free, no «sin '
          'límite»', (tester) async {
        await tester.pumpWidget(_harness(
          links: [_link('a1', TrainerLinkStatus.active)],
          profile: pf(
            status: SubscriptionStatus.cancelled,
            tier: SubscriptionTier.plan3,
            weightLimit: null,
            fin: vencida,
          ),
        ));
        await tester.pump();

        expect(find.text('TREINO Coach · Free'), findsOneWidget);
        expect(find.text('TREINO Coach · Plan 3'), findsNothing);
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.textContaining('sin límite'), findsNothing);
      });

      // El otro lado de la regla: mientras la baja corre, manda el doc. El
      // fixture pone `weightLimit: 9`, distinto del 7 de la tabla, justamente
      // para que se vea de dónde sale el número.
      testWidgets(
          'baja con días pagos: sigue el plan del doc, con el weightLimit del '
          'doc, y sin línea de plantillas', (tester) async {
        await tester.pumpWidget(_harness(
          links: [_link('a1', TrainerLinkStatus.active)],
          templateUsage: Stream.value((limit: 3, count: 2)),
          profile: pf(
            status: SubscriptionStatus.cancelled,
            weightLimit: 9,
            fin: conDiasPagos,
          ),
        ));
        await tester.pump();

        expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
        expect(find.text('TREINO Coach · Free'), findsNothing);
        expect(find.text('1 / 9'), findsOneWidget);
        // Plan 1 no tiene tope de plantillas: la línea no aparece aunque el
        // provider traiga datos (mismo criterio que el plan activo).
        expect(find.textContaining('Plantillas'), findsNothing);
      });

      // REGRESIÓN: un plan activo sigue leyendo el tope del doc.
      testWidgets(
          'plan activo: sigue el plan del doc con el weightLimit del doc',
          (tester) async {
        await tester.pumpWidget(_harness(
          links: [_link('a1', TrainerLinkStatus.active)],
          profile: pf(weightLimit: 9),
        ));
        await tester.pump();

        expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
        expect(find.text('1 / 9'), findsOneWidget);
      });
    });

    // REGRESIÓN: lo que no es una baja queda como estaba — aunque el período
    // del doc esté vencido, la línea y el ocultamiento son sólo de `cancelled`.
    for (final status in SubscriptionStatus.values) {
      if (status == SubscriptionStatus.cancelled) continue;

      testWidgets('$status sigue ofreciendo dar de baja y sin línea de baja',
          (tester) async {
        await tester.pumpWidget(_harness(
          links: const [],
          profile: pf(status: status, fin: DateTime.utc(2026, 9, 30, 15)),
        ));
        await tester.pump();

        expect(linkDeBaja, findsOneWidget);
        expect(lineaDeBaja, findsNothing);
        // La card sigue con el tier del doc: sólo una BAJA vencida cambia el
        // plan que se muestra.
        expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
      });
    }

    // Free nunca tuvo qué dar de baja: no cambia.
    testWidgets('sin suscripción (Free): no ofrece dar de baja',
        (tester) async {
      await tester.pumpWidget(_harness(links: const []));
      await tester.pump();

      expect(linkDeBaja, findsNothing);
      expect(lineaDeBaja, findsNothing);
      expect(find.text('TREINO Coach · Free'), findsOneWidget);
    });
  });
}
