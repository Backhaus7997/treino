// custom_exercise_limit_notice_test.dart — el aviso que
// [intentarCrearEjercicioPropio] muestra cuando el PF choca el tope
// (docs/limite-ejercicios-pf.md PR3, "Los avisos").
//
// Cubre lo que el resto de los tests de entrada NO puede cubrir en detalle:
// los DOS estados (en el tope / pasado de tope) en las DOS superficies, la
// pluralización de "borrá N", y que ningún `null` se interpola.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/custom_exercise_limit_notice.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<void> _mostrar(
  WidgetTester tester, {
  required int limit,
  required int count,
  CustomExerciseLimitNoticeForm? form,
}) async {
  debugCustomExerciseLimitNoticeForm = form;
  addTearDown(() => debugCustomExerciseLimitNoticeForm = null);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCustomExerciseLimitNotice(context,
                limit: limit, count: count),
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
  group('móvil (sheet) — sólo estado', () {
    testWidgets('en el tope: el texto exacto del plan, sin botón de acción',
        (tester) async {
      await _mostrar(
        tester,
        limit: 60,
        count: 60,
        form: CustomExerciseLimitNoticeForm.sheet,
      );

      expect(
        find.text('Llegaste a los 60 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsOneWidget,
      );
      // Sólo el dismiss — nada que ofrezca comprar.
      expect(find.byKey(const Key('custom_exercise_limit_dismiss')),
          findsOneWidget);
      expect(find.text('VER PLANES'), findsNothing);
    });

    testWidgets('pasado de tope, toDelete > 1: número pelado sin "ejercicio"',
        (tester) async {
      await _mostrar(
        tester,
        limit: 60,
        count: 80,
        form: CustomExerciseLimitNoticeForm.sheet,
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
      // borde de E6 y esta rama se vuelve alcanzable.
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
        limit: 20,
        count: 20,
        form: CustomExerciseLimitNoticeForm.sheet,
      );

      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(textos.toLowerCase().contains('null'), isFalse);
    });
  });

  group('web (dialog) — con VER PLANES', () {
    testWidgets('en el tope: cuerpo + VER PLANES', (tester) async {
      await _mostrar(
        tester,
        limit: 60,
        count: 60,
        form: CustomExerciseLimitNoticeForm.dialog,
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
        limit: 60,
        count: 80,
        form: CustomExerciseLimitNoticeForm.dialog,
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
      debugCustomExerciseLimitNoticeForm = CustomExerciseLimitNoticeForm.dialog;
      addTearDown(() => debugCustomExerciseLimitNoticeForm = null);

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (context, _) => Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showCustomExerciseLimitNotice(
                    context,
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

  group('resolución de superficie sin el seam de test', () {
    testWidgets('sin override, kIsWeb == false bajo flutter test ⇒ sheet',
        (tester) async {
      await _mostrar(tester, limit: 20, count: 20);

      expect(find.byKey(const Key('custom_exercise_limit_dismiss')),
          findsOneWidget);
      expect(find.text('VER PLANES'), findsNothing);
    });
  });
}
