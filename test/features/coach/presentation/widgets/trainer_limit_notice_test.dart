// trainer_limit_notice_test.dart — el aviso que
// [intentarCrearEjercicioPropio] e [intentarCrearPlantilla] muestran cuando
// el PF choca un tope de su plan (docs/limite-ejercicios-pf.md PR3 y
// docs/limite-plantillas-pf.md PR3, "Los avisos").
//
// Cubre lo que el resto de los tests de entrada NO puede cubrir en detalle:
// los DOS estados (en el tope / pasado de tope) en las DOS superficies, para
// los DOS `kind`, la pluralización, y que ningún `null` se interpola.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_limit_notice.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<void> _mostrar(
  WidgetTester tester, {
  required TrainerLimitKind kind,
  required int limit,
  required int count,
  TrainerLimitNoticeForm? form,
}) async {
  debugTrainerLimitNoticeForm = form;
  addTearDown(() => debugTrainerLimitNoticeForm = null);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTrainerLimitNotice(context,
                kind: kind, limit: limit, count: count),
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
  group('móvil (sheet) — sólo estado — ejercicios propios', () {
    testWidgets('en el tope: el texto exacto del plan, sin botón de acción',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 60,
        count: 60,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(
        find.text('Llegaste a los 60 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsOneWidget,
      );
      // Sólo el dismiss — nada que ofrezca comprar.
      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
      expect(find.text('VER PLANES'), findsNothing);
    });

    testWidgets('pasado de tope, toDelete > 1: número pelado sin "ejercicio"',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 60,
        count: 80,
        form: TrainerLimitNoticeForm.sheet,
      );

      // Texto exacto del plan (docs/limite-ejercicios-pf.md PR3, "Los
      // avisos"): toDelete = 80 - 60 + 1 = 21.
      expect(
        find.text('Tenés 80 ejercicios propios y tu plan incluye 60. '
            'Conservás todos; para crear uno nuevo, borrá 21.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'toDelete == 1 (por más que hoy sea inalcanzable desde el widget: '
        'overLimit exige count > limit, así que toDelete = count - limit + 1 '
        'nunca baja de 2) ⇒ la cadena ICU igual dice el singular',
        (tester) async {
      // No se puede llegar a este texto TAPEANDO el aviso — se prueba la
      // función de l10n directo, como defensa si el día de mañana cambia el
      // borde y esta rama se vuelve alcanzable.
      late String cuerpo;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: Builder(
            builder: (context) {
              cuerpo =
                  AppL10n.of(context).customExerciseLimitOverBody(61, 60, 1);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        cuerpo,
        'Tenés 61 ejercicios propios y tu plan incluye 60. Conservás '
        'todos; para crear uno nuevo, borrá 1 ejercicio.',
      );
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
  });

  group('web (dialog) — con VER PLANES — ejercicios propios', () {
    testWidgets('en el tope: cuerpo + VER PLANES', (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
        limit: 60,
        count: 60,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsOneWidget);
      expect(
        find.text('Tu plan incluye 60 ejercicios propios y ya tenés 60.'),
        findsOneWidget,
      );
      expect(find.text('VER PLANES'), findsOneWidget);
    });

    testWidgets(
        'pasado de tope: mismo texto de conservación que el móvil, '
        'más el botón', (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.customExercises,
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
  });

  group('móvil (sheet) — sólo estado — plantillas', () {
    testWidgets('en el tope: el texto exacto del plan, sin botón de acción',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 3,
        form: TrainerLimitNoticeForm.sheet,
      );

      expect(
        find.text('Llegaste a las 3 plantillas de tu plan. Podés editarlas, '
            'asignarlas o archivar una para hacer lugar.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
      expect(find.text('VER PLANES'), findsNothing);
    });

    testWidgets('pasado de tope: conservás todas, número pelado a archivar',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
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
  });

  group('web (dialog) — con VER PLANES — plantillas', () {
    testWidgets('en el tope: título y cuerpo de plantillas + VER PLANES',
        (tester) async {
      await _mostrar(
        tester,
        kind: TrainerLimitKind.templates,
        limit: 3,
        count: 3,
        form: TrainerLimitNoticeForm.dialog,
      );

      expect(find.text('TOPE DE PLANTILLAS'), findsOneWidget);
      expect(
        find.text('Tu plan incluye 3 plantillas y ya tenés 3.'),
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
      expect(find.text('VER PLANES'), findsNothing);
    });
  });
}
