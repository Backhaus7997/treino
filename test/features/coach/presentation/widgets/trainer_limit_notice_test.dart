// trainer_limit_notice_test.dart — el aviso que
// [intentarCrearEjercicioPropio] e [intentarCrearPlantilla] muestran cuando
// el PF choca un tope de su plan (docs/limite-ejercicios-pf.md PR3 y
// docs/limite-plantillas-pf.md PR3, "Los avisos").
//
// Desde la unificación con `plan_limit_paywall.dart` (el paywall de
// alumnos), este aviso usa el MISMO estilo: candado, "en el tope" con caja
// de upsell y precio, "pasado de tope" con el texto de conservación, VER
// PLANES y "Ahora no". Este archivo cubre los DOS estados en las DOS
// superficies, para los DOS `kind`, la caja de upsell y que ningún `null` se
// interpola.
//
// Cambio 2 (2026-09-29, hallazgo P1 de Codex): el tier que el aviso NOMBRA
// se resuelve desde el `limit` del servidor, no del tier nominal a ciegas —
// ver `resolveNoticeTier` y su grupo de tests acá abajo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_limit_notice.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<void> _mostrar(
  WidgetTester tester, {
  required TrainerLimitKind kind,
  SubscriptionTier currentTier = SubscriptionTier.free,
  // Default `active`: la inmensa mayoría de estos tests no está probando el
  // estado de la suscripción — sólo los del grupo "inactiva por ESTADO" lo
  // pisan explícitamente.
  SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
  DateTime? currentPeriodEnd,
  required int limit,
  required int count,
  TrainerLimitNoticeForm? form,
  // Default es_AR: mismo idioma que hoy hablan los strings hardcodeados de
  // este aviso. El grupo "inglés" de más abajo lo pisa explícitamente.
  Locale locale = const Locale('es', 'AR'),
}) async {
  debugTrainerLimitNoticeForm = form;
  addTearDown(() => debugTrainerLimitNoticeForm = null);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      // Sin esto, el `build` de `_TrainerLimitContent` revienta con "Null
      // check operator used on a null value" apenas toca AppL10n (mismo
      // motivo que documenta `custom_exercise_limit_gate_test.dart`).
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTrainerLimitNotice(
              context,
              kind: kind,
              currentTier: currentTier,
              subscriptionStatus: subscriptionStatus,
              currentPeriodEnd: currentPeriodEnd,
              limit: limit,
              count: count,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('resolveNoticeTier — Cambio 2 (P1: nombrar el tier EFECTIVO)', () {
    test('nominal == efectivo, activa: resuelve el mismo tier, no inactiva',
        (() {
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 60,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.active,
      );
      expect(r.tier, SubscriptionTier.plan1);
      expect(r.inactive, isFalse);
    }));

    test('piso prepago: el efectivo es MAYOR que el nominal, no inactiva', (() {
      // El nominal es Free pero el limit que bloqueó es el de Plan 2 (120) —
      // un piso prepago subió el efectivo por encima de lo que el PF pagó.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 120,
        nominalTier: SubscriptionTier.free,
        subscriptionStatus: SubscriptionStatus.active,
      );
      expect(r.tier, SubscriptionTier.plan2);
      expect(r.inactive, isFalse);
    }));

    test('límite que no coincide con ningún tier ⇒ genérico (tier null)', (() {
      // 45 no es ni 20 (Free) ni 60 (Plan 1) ni 120 (Plan 2): un tope
      // ajustado a mano. No se puede afirmar qué plan lo explica.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 45,
        nominalTier: SubscriptionTier.free,
        subscriptionStatus: SubscriptionStatus.active,
      );
      expect(r.tier, isNull);
      expect(r.inactive, isFalse);
    }));

    test('plantillas: sólo Free tiene tope, cualquier otro límite es genérico',
        (() {
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.templates,
        limit: 10,
        nominalTier: SubscriptionTier.free,
        subscriptionStatus: SubscriptionStatus.active,
      );
      expect(r.tier, isNull);
      expect(r.inactive, isFalse);
    }));

    test('inactive nunca es true sin un tier resuelto', (() {
      // Contrato del dartdoc: `inactive` sólo puede ser `true` cuando `tier`
      // no es null. Un límite sin match no puede además decir "inactiva",
      // ni siquiera con el estado caído.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 999,
        nominalTier: SubscriptionTier.free,
        subscriptionStatus: SubscriptionStatus.paused,
      );
      expect(r.tier, isNull);
      expect(r.inactive, isFalse);
    }));
  });

  group(
      'resolveNoticeTier — inactive por ESTADO, no por comparación de '
      'límites (segundo hallazgo Codex, 2026-09-29)', () {
    test('pausada ⇒ inactiva, nombra el efectivo (Free)', (() {
      // El caso textual del hallazgo: un Plan 1 PAUSADO con 3 plantillas
      // (Plan 1 nominal no tiene tope de plantillas — sólo Free lo tiene).
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.templates,
        limit: 3,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.paused,
      );
      expect(r.tier, SubscriptionTier.free);
      expect(r.inactive, isTrue);
    }));

    test('pending ⇒ inactiva', (() {
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.pending,
      );
      expect(r.tier, SubscriptionTier.free);
      expect(r.inactive, isTrue);
    }));

    test('cancelled con currentPeriodEnd VENCIDO ⇒ inactiva', (() {
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.cancelled,
        currentPeriodEnd: DateTime.utc(2026, 1, 1),
        now: DateTime.utc(2026, 2, 1),
      );
      expect(r.tier, SubscriptionTier.free);
      expect(r.inactive, isTrue);
    }));

    test(
        'cancelled con currentPeriodEnd VIGENTE + límite ya caído a Free '
        '⇒ genérico, NUNCA inactiva', (() {
      // Dentro del período pagado el servidor todavía respeta el tier
      // nominal (`limiteDelStatus` en effective-limit.ts) — si el `limit`
      // que bloqueó igual muestra Free es una propagación atrasada, no un
      // hecho sobre la cancelación. Mismo eje que el caso "activa" de abajo.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.cancelled,
        currentPeriodEnd: DateTime.utc(2026, 3, 1),
        now: DateTime.utc(2026, 2, 1),
      );
      expect(r.tier, isNull);
      expect(r.inactive, isFalse);
    }));

    test('grace cuenta como activa: nombra el nominal, no inactiva', (() {
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 60,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.grace,
      );
      expect(r.tier, SubscriptionTier.plan1);
      expect(r.inactive, isFalse);
    }));

    test(
        'EL BUG: activa con el límite todavía en Free (propagación '
        'pendiente) ⇒ genérico, NUNCA "no está activa"', (() {
      // Éste es el caso que rompía antes de este fix: comparar límites
      // (efectivo Free < nominal Plan 1) decía "inactiva" con la
      // suscripción realmente activa — falso, AGENTS.md §11.1.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.active,
      );
      expect(r.tier, isNull);
      expect(r.inactive, isFalse);
    }));

    test('piso prepago gana aunque el estado esté caído (pausada)', (() {
      // Un piso prepago vigente no pasa por el switch de status (mismo
      // criterio que `conPisoPrepago` del servidor): aunque la suscripción
      // NUEVA esté pausada, el piso de la VIEJA sigue de pie.
      final r = resolveNoticeTier(
        kind: TrainerLimitKind.customExercises,
        limit: 120,
        nominalTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.paused,
      );
      expect(r.tier, SubscriptionTier.plan2);
      expect(r.inactive, isFalse);
    }));
  });

  group('móvil (sheet) — en el tope — ejercicios propios', () {
    testWidgets('mismo tono que el paywall de alumnos, con upsell',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.free,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsOneWidget);
      // Móvil, decisión del dueño 2026-09-29: sin "para sumar más, subí de
      // plan" (Guideline 3.1.3(f)) — ver
      // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
      expect(
        find.text(
          'Tu plan Free incluye 20 ejercicios propios. Podés editar o '
          'borrar los que ya tenés.',
        ),
        findsOneWidget,
      );
      // La caja de upsell al siguiente tier, mismo estilo que el paywall de
      // alumnos — sin "PASATE A" en el móvil: sólo el nombre del plan.
      expect(find.text('PLAN 1'), findsOneWidget);
      expect(find.textContaining('PASATE A'), findsNothing);
      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('Hasta 60 ejercicios propios'), findsOneWidget);
      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
      expect(find.byKey(const Key('trainer_limit_ver_planes')), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
      // "Entendido" y no "Ahora no": no presupone ninguna oferta.
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('desde Plan 2, el upsell dice "sin límite" y nunca "null"',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan2,
        limit: 120,
        count: 120,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(find.text('PLAN 3'), findsOneWidget);
      expect(find.textContaining('PASATE A'), findsNothing);
      expect(find.text('Ejercicios propios sin límite'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    // ── Cambio 2 (P1): el tier que se NOMBRA sale del limit, no del nominal
    // ─────────────────────────────────────────────────────────────────────

    testWidgets(
        'suscripción Plan 1 PAUSADA: nombra Free (no Plan 1) y no ofrece '
        'upsell', (tester) async {
      // El limit que bloqueó (20) es el de Free — el servidor ya calculó el
      // efectivo. El nominal (plan1) sólo debe aparecer para decir que ESE
      // es el que no está activo. El estado (pausada) es lo que autoriza
      // "inactiva" — no la comparación de límites (segundo hallazgo Codex).
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.paused,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(
        find.text('Tu suscripción a Plan 1 no está activa. Mientras tanto, '
            'tu plan Free incluye 20 ejercicios propios.'),
        findsOneWidget,
      );
      expect(find.textContaining('Plan 1 incluye'), findsNothing);
      expect(find.textContaining('PASATE A'), findsNothing);
      expect(find.text('PLAN 2'), findsNothing);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets(
        'Plan 1 ACTIVA con el límite todavía en Free (propagación '
        'pendiente): genérico, nunca "no está activa"', (tester) async {
      // Mismo limit/nominal que el test de arriba — la ÚNICA diferencia es
      // el estado. Antes de este fix, los dos test producían el mismo
      // resultado ("inactiva"), que es exactamente el bug: comparar límites
      // no distingue "pausada" de "activa con propagación atrasada".
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.active,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(find.textContaining('no está activa'), findsNothing);
      expect(
        find.text('Tu plan incluye 20 ejercicios propios. Podés editar o '
            'borrar los que ya tenés.'),
        findsOneWidget,
      );
      expect(find.textContaining('Plan 1 incluye'), findsNothing);
      expect(find.textContaining('Free incluye'), findsNothing);
      expect(find.text('PLAN 2'), findsNothing);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets(
        'piso prepago: nombra el tier MAYOR (Plan 2, no Free) y ofrece su '
        'upsell', (tester) async {
      // Nominal Free, pero el limit que bloqueó (120) es el de Plan 2: un
      // piso prepago subió el efectivo por encima de lo que el PF pagó.
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 120,
        count: 120,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(
        find.text('Tu plan Plan 2 incluye 120 ejercicios propios. Podés '
            'editar o borrar los que ya tenés.'),
        findsOneWidget,
      );
      expect(find.text('PLAN 3'), findsOneWidget);
      expect(find.text('Ejercicios propios sin límite'), findsOneWidget);
    });

    testWidgets(
        'límite ajustado a mano: cuerpo genérico, sin nombrar un plan ni '
        'ofrecer upsell', (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 45,
        count: 45,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(
        find.text('Tu plan incluye 45 ejercicios propios. Podés editar o '
            'borrar los que ya tenés.'),
        findsOneWidget,
      );
      expect(find.textContaining('Free incluye'), findsNothing);
      // Sin caja de upsell: no hay un tier de referencia desde el cual
      // calcular "el siguiente" sin adivinar.
      expect(find.text('PLAN 1'), findsNothing);
      expect(find.text('PLAN 2'), findsNothing);
      expect(find.text('PLAN 3'), findsNothing);
      expect(find.text('PLAN A MEDIDA'), findsNothing);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets('pasado de tope: conservación, SIN caja de upsell',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        limit: 60,
        count: 80,
        form: TrainerLimitNoticeForm.sheet,
      );

      // toDelete = 80 - 60 + 1 = 21.
      expect(
        find.text('Tenés 80 ejercicios propios y tu plan incluye 60. '
            'Conservás todos; para crear uno nuevo, borrá 21.'),
        findsOneWidget,
      );
      expect(find.textContaining('PASATE A'), findsNothing);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets('ningún texto visible interpola "null"', (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.sheet,
      );

      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(textos.toLowerCase().contains('null'), isFalse);
    });

    testWidgets('VER PLANES navega a /facturacion/planes y cierra el sheet',
        (tester) async {
      debugTrainerLimitNoticeForm = TrainerLimitNoticeForm.sheet;
      addTearDown(() => debugTrainerLimitNoticeForm = null);

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showTrainerLimitNotice(
                    context,
                    kind: TrainerLimitKind.customExercises,
                    currentTier: SubscriptionTier.free,
                    subscriptionStatus: SubscriptionStatus.active,
                    limit: 60,
                    count: 60,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/planes',
            builder: (context, _) => const Scaffold(body: Text('PLANES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark(),
          // Sin esto, `_TrainerLimitContent` revienta con "Null check
          // operator used on a null value" apenas toca AppL10n — estos 4
          // harnesses arman su propio router y no pasan por `_mostrar()`.
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('VER PLANES'));
      await tester.pumpAndSettle();

      expect(
        find.text('TOPE DE EJERCICIOS PROPIOS'),
        findsNothing,
        reason: 'el sheet se cierra antes de navegar',
      );
      expect(find.text('PLANES'), findsOneWidget);
    });
  });

  group('web (dialog) — con VER PLANES — ejercicios propios', () {
    testWidgets('en el tope: mismo cuerpo que el móvil + VER PLANES',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.free,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsOneWidget);
      expect(
        find.text(
          'Tu plan Free incluye 20 ejercicios propios. Para sumar más, '
          'subí de plan.',
        ),
        findsOneWidget,
      );
      expect(find.text('PASATE A PLAN 1'), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets(
        'pasado de tope: mismo texto de conservación que el móvil, '
        'más el botón', (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        limit: 60,
        count: 80,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(
        find.text('Tenés 80 ejercicios propios y tu plan incluye 60. '
            'Conservás todos; para crear uno nuevo, borrá 21.'),
        findsOneWidget,
      );
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets('VER PLANES navega a /facturacion/planes y cierra el diálogo',
        (tester) async {
      debugTrainerLimitNoticeForm = TrainerLimitNoticeForm.dialog;
      addTearDown(() => debugTrainerLimitNoticeForm = null);

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showTrainerLimitNotice(
                    context,
                    kind: TrainerLimitKind.customExercises,
                    currentTier: SubscriptionTier.free,
                    subscriptionStatus: SubscriptionStatus.active,
                    limit: 60,
                    count: 60,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/planes',
            builder: (context, _) => const Scaffold(body: Text('PLANES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark(),
          // Sin esto, `_TrainerLimitContent` revienta con "Null check
          // operator used on a null value" apenas toca AppL10n — estos 4
          // harnesses arman su propio router y no pasan por `_mostrar()`.
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('VER PLANES'));
      await tester.pumpAndSettle();

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsNothing,
          reason: 'el diálogo se cierra antes de navegar');
      expect(find.text('PLANES'), findsOneWidget);
    });

    // ── Segundo hallazgo (Codex, 2026-09-29): foco y activación por teclado
    // ─────────────────────────────────────────────────────────────────────
    // Antes, "VER PLANES" y el descarte eran `TreinoTappable` pelado — sin
    // `FocusNode`, invisibles para Tab y para Enter/Espacio. En el dialog
    // WEB del Coach Hub, quien navega sólo con teclado no podía llegar a
    // ninguno de los dos.

    testWidgets('VER PLANES es alcanzable con Tab y se activa con Enter',
        (tester) async {
      debugTrainerLimitNoticeForm = TrainerLimitNoticeForm.dialog;
      addTearDown(() => debugTrainerLimitNoticeForm = null);

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showTrainerLimitNotice(
                    context,
                    kind: TrainerLimitKind.customExercises,
                    currentTier: SubscriptionTier.free,
                    subscriptionStatus: SubscriptionStatus.active,
                    limit: 60,
                    count: 60,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/planes',
            builder: (context, _) => const Scaffold(body: Text('PLANES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark(),
          // Sin esto, `_TrainerLimitContent` revienta con "Null check
          // operator used on a null value" apenas toca AppL10n — estos 4
          // harnesses arman su propio router y no pasan por `_mostrar()`.
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // "VER PLANES" es el primer control enfocable del diálogo (candado y
      // caja de upsell son puramente informativos, sin foco).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        find.text('TOPE DE EJERCICIOS PROPIOS'),
        findsNothing,
        reason: 'el diálogo se cierra antes de navegar',
      );
      expect(find.text('PLANES'), findsOneWidget);
    });

    testWidgets('el descarte cierra el diálogo con Tab, Tab y Enter',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.free,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.dialog,
      );

      // VER PLANES primero, "Ahora no" segundo — mismo orden de traversal.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsNothing);
    });
  });

  group('móvil (sheet) — plantillas', () {
    testWidgets('en el tope: mismo tono que alumnos, con upsell',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        currentTier: SubscriptionTier.free,
        limit: 3,
        count: 3,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(find.text('TOPE DE PLANTILLAS'), findsOneWidget);
      // Móvil: sin "para sumar más, subí de plan" (3.1.3(f)).
      expect(
        find.text('Tu plan Free incluye 3 plantillas. Podés editar o '
            'archivar las que ya tenés.'),
        findsOneWidget,
      );
      expect(find.text('PLAN 1'), findsOneWidget);
      expect(find.textContaining('PASATE A'), findsNothing);
      // Free → Plan 1 ya es plantillas sin límite (sólo Free tiene tope).
      expect(find.text('Plantillas sin límite'), findsOneWidget);
      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
      expect(find.byKey(const Key('trainer_limit_ver_planes')), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets('pasado de tope: conservás todas, número pelado a archivar',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        currentTier: SubscriptionTier.free,
        limit: 3,
        count: 5,
        form: TrainerLimitNoticeForm.sheet,
      );

      // toArchive = 5 - 3 + 1 = 3.
      expect(
        find.text('Tenés 5 plantillas y tu plan incluye 3. Conservás '
            'todas; para crear una nueva, archivá 3.'),
        findsOneWidget,
      );
      expect(find.textContaining('PASATE A'), findsNothing);
    });

    testWidgets('el texto no nombra "web", "mail" ni "pasá a un plan"',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 3,
        form: TrainerLimitNoticeForm.sheet,
      );

      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase())
          .join('\n');
      expect(textos.contains('web'), isFalse);
      expect(textos.contains('mail'), isFalse);
      expect(textos.contains('pasá a un plan'), isFalse);
      expect(textos.contains('null'), isFalse);
    });

    testWidgets('VER PLANES navega a /facturacion/planes y cierra el sheet',
        (tester) async {
      debugTrainerLimitNoticeForm = TrainerLimitNoticeForm.sheet;
      addTearDown(() => debugTrainerLimitNoticeForm = null);

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showTrainerLimitNotice(
                    context,
                    kind: TrainerLimitKind.templates,
                    currentTier: SubscriptionTier.free,
                    subscriptionStatus: SubscriptionStatus.active,
                    limit: 3,
                    count: 3,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/planes',
            builder: (context, _) => const Scaffold(body: Text('PLANES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.dark(),
          // Sin esto, `_TrainerLimitContent` revienta con "Null check
          // operator used on a null value" apenas toca AppL10n — estos 4
          // harnesses arman su propio router y no pasan por `_mostrar()`.
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('VER PLANES'));
      await tester.pumpAndSettle();

      expect(find.text('TOPE DE PLANTILLAS'), findsNothing,
          reason: 'el sheet se cierra antes de navegar');
      expect(find.text('PLANES'), findsOneWidget);
    });
  });

  group('web (dialog) — plantillas', () {
    testWidgets('en el tope: título y cuerpo de plantillas + VER PLANES',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        currentTier: SubscriptionTier.free,
        limit: 3,
        count: 3,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(find.text('TOPE DE PLANTILLAS'), findsOneWidget);
      expect(
        find.text('Tu plan Free incluye 3 plantillas. Para sumar más, '
            'subí de plan.'),
        findsOneWidget,
      );
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    // El bug real: "plantillas" es femenino y "ejercicios" masculino — un
    // texto calcado sin ajustar el género dice "para crear UNO nuevo" sobre
    // una plantilla, y "conservás TODOS" en vez de "todas".
    testWidgets('pasado de tope: género correcto ("una nueva", "todas")',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        currentTier: SubscriptionTier.free,
        limit: 3,
        count: 5,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(
        find.text('Tenés 5 plantillas y tu plan incluye 3. Conservás '
            'todas; para crear una nueva, archivá 3.'),
        findsOneWidget,
      );
    });
  });

  group('resolución de superficie sin el seam de test', () {
    testWidgets('sin override, kIsWeb == false bajo flutter test ⇒ sheet',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );

      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
    });
  });

  // ── Inglés (hallazgo Codex, PR #1266) ───────────────────────────────────
  //
  // Antes de esta rama, ejercicios propios y plantillas leían sus textos de
  // AppL10n (con su versión en inglés en `intl_en.arb`); la unificación con el
  // paywall de alumnos los hardcodeó en castellano y borró esas claves. Este
  // grupo cubre CADA estado del aviso móvil —en el tope con tier, pasado de
  // tope, suscripción inactiva, piso prepago y cuerpo genérico— en
  // Locale('en'), para los dos `kind`.
  //
  // Ojo: hoy `resolveLocale` (ADR-I18N-005) fuerza es_AR en producción, así
  // que estos textos sólo se ven con un Locale explícito como el de acá. El
  // día que se levante esa traba tienen que estar, y este grupo es lo que
  // garantiza que estén.

  group('móvil (sheet) — Locale(en)', () {
    Future<void> mostrarEn(
      WidgetTester tester, {
      required TrainerLimitKind kind,
      SubscriptionTier currentTier = SubscriptionTier.free,
      SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
      required int limit,
      required int count,
    }) =>
        _mostrar(
          tester,
          kind: kind,
          currentTier: currentTier,
          subscriptionStatus: subscriptionStatus,
          limit: limit,
          count: count,
          form: TrainerLimitNoticeForm.sheet,
          locale: const Locale('en'),
        );

    testWidgets(
        'ejercicios propios, en el tope: título, cuerpo, tarjeta y botones '
        'en inglés', (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
      );

      expect(find.text('CUSTOM EXERCISE LIMIT'), findsOneWidget);
      expect(
        find.text(
          'Your Free plan includes 20 custom exercises. You can edit or '
          'delete the ones you already have.',
        ),
        findsOneWidget,
      );
      // La tarjeta del siguiente plan: nombre, precio, sufijo y beneficio.
      expect(find.text('PLAN 1'), findsOneWidget);
      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('/month'), findsOneWidget);
      expect(find.text('/mes'), findsNothing);
      expect(find.text('Up to 60 custom exercises'), findsOneWidget);
      expect(find.text('VIEW PLANS'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('VER PLANES'), findsNothing);
      expect(find.text('Entendido'), findsNothing);
    });

    testWidgets('ejercicios propios, desde Plan 2: "Unlimited", nunca "null"',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan2,
        limit: 120,
        count: 120,
      );

      expect(find.text('PLAN 3'), findsOneWidget);
      expect(find.text('Unlimited custom exercises'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('ejercicios propios, pasado de tope: cuerpo en inglés',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        limit: 60,
        count: 80,
      );

      // toDelete = 80 - 60 + 1 = 21.
      expect(
        find.text(
          'You have 80 custom exercises and your plan includes 60. You '
          'keep them all; to create a new one, delete 21.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'ejercicios propios, suscripción pausada (límite de Free): '
        'cuerpo en inglés, sin upsell', (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        currentTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.paused,
        limit: 20,
        count: 20,
      );

      expect(find.text('CUSTOM EXERCISE LIMIT'), findsOneWidget);
      expect(
        find.text(
          "Your Plan 1 subscription isn't active. Meanwhile, your Free "
          'plan includes 20 custom exercises.',
        ),
        findsOneWidget,
      );
      expect(find.text('PLAN 2'), findsNothing);
    });

    testWidgets(
        'ejercicios propios, límite ajustado a mano: cuerpo genérico en '
        'inglés', (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 45,
        count: 45,
      );

      expect(
        find.text(
          'Your plan includes 45 custom exercises. You can edit or delete '
          'the ones you already have.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ejercicios propios, límite 1: singular ("1 custom exercise")',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 1,
        count: 1,
      );

      expect(
        find.text(
          'Your plan includes 1 custom exercise. You can edit or delete '
          'the ones you already have.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('plantillas, en el tope: título, cuerpo y tarjeta en inglés',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 3,
      );

      expect(find.text('TEMPLATE LIMIT'), findsOneWidget);
      expect(
        find.text(
          'Your Free plan includes 3 templates. You can edit or archive '
          'the ones you already have.',
        ),
        findsOneWidget,
      );
      expect(find.text('/month'), findsOneWidget);
      expect(find.text('Unlimited templates'), findsOneWidget);
      expect(find.text('VIEW PLANS'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('plantillas, pasado de tope: cuerpo en inglés', (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 5,
      );

      expect(
        find.text(
          'You have 5 templates and your plan includes 3. You keep them '
          'all; to create a new one, archive 3.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('plantillas, suscripción pausada: cuerpo en inglés',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.templates,
        currentTier: SubscriptionTier.plan1,
        subscriptionStatus: SubscriptionStatus.paused,
        limit: 3,
        count: 3,
      );

      expect(find.text('TEMPLATE LIMIT'), findsOneWidget);
      expect(
        find.text(
          "Your Plan 1 subscription isn't active. Meanwhile, your Free "
          'plan includes 3 templates.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('plantillas, límite ajustado a mano: cuerpo genérico en inglés',
        (tester) async {
      await mostrarEn(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 10,
        count: 10,
      );

      expect(
        find.text(
          'Your plan includes 10 templates. You can edit or archive the '
          'ones you already have.',
        ),
        findsOneWidget,
      );
    });

    // Control: la WEB no se tradujo — sigue en castellano aunque el Locale
    // sea inglés (convención vigente del Coach Hub: i18n Fase W3). Si este
    // test se pusiera rojo, alguien tradujo la web sin querer.
    testWidgets('control: en WEB con Locale(en) TODO sigue en español',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 20,
        count: 20,
        form: TrainerLimitNoticeForm.dialog,
        locale: const Locale('en'),
      );

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsOneWidget);
      expect(
        find.text(
          'Tu plan Free incluye 20 ejercicios propios. Para sumar más, '
          'subí de plan.',
        ),
        findsOneWidget,
      );
      expect(find.text('/mes'), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
      expect(find.text('CUSTOM EXERCISE LIMIT'), findsNothing);
      expect(find.text('/month'), findsNothing);
    });
  });
}
