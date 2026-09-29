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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_limit_notice.dart';

Future<void> _mostrar(
  WidgetTester tester, {
  required TrainerLimitKind kind,
  SubscriptionTier currentTier = SubscriptionTier.free,
  required int limit,
  required int count,
  TrainerLimitNoticeForm? form,
}) async {
  debugTrainerLimitNoticeForm = form;
  addTearDown(() => debugTrainerLimitNoticeForm = null);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTrainerLimitNotice(
              context,
              kind: kind,
              currentTier: currentTier,
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
}
