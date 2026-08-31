// Geometría de los botones de acción del editor de rutina y del bloque de
// superserie (#869).
//
// El bug que este slice arregla no era de color sino de FORMA: `+ Agregar set`,
// `Agregar ejercicio` y `+ Superserie` eran tres `TextButton.icon` sin
// contenedor, con tres márgenes distintos y sin alto compartido. Se leían como
// una lista despareja de links. Estos tests afirman lo que los volvió botones.
//
// Son de widget aislado y no del editor completo a propósito: la geometría es
// del componente, y montar la pantalla entera para medir un alto agrega 5.000
// líneas de superficie a un test que sólo mira una caja.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/workout/presentation/widgets/routine_action_buttons.dart';
import 'package:treino/features/workout/presentation/widgets/superset_block.dart';

/// Alto que el slice le fija a las tres acciones. Vive acá y en
/// `routine_action_buttons.dart`: si divergen, este test lo dice.
const double _kAltoEsperado = 48;

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  double ancho = 400,
  ThemeData? tema,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: ancho, child: hijo),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// El nodo semántico del botón con [key].
///
/// `getSemantics(find.byKey(...))` no sirve acá: la key está en el widget
/// externo, cuyo `SizedBox` no produce semántica propia, así que el finder sube
/// hasta la raíz y devuelve el nodo de la pantalla entera. El nodo del botón
/// cuelga del `MergeSemantics` que junta rol y label.
Finder _nodoDe(Key key) => find.descendant(
      of: find.byKey(key),
      matching: find.byType(MergeSemantics),
    );

void main() {
  group('DayActionButtons — una sola geometría para las dos acciones', () {
    testWidgets('los dos botones miden lo mismo de alto', (tester) async {
      await _montar(
        tester,
        DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: () {},
          supersetLabel: '+ Superserie',
          onAddSuperset: () {},
        ),
      );

      final ejercicio =
          tester.getSize(find.byKey(const Key('day_add_exercise_button')));
      final superserie =
          tester.getSize(find.byKey(const Key('add_superset_button')));

      expect(ejercicio.height, _kAltoEsperado);
      expect(superserie.height, _kAltoEsperado);
      expect(
        ejercicio.height,
        superserie.height,
        reason: 'Que los dos midan igual ES el arreglo: antes cada uno traía '
            'el padding que le tocaba de su TextButton.',
      );
    });

    testWidgets('comparten el borde superior — están en la misma fila',
        (tester) async {
      await _montar(
        tester,
        DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: () {},
          supersetLabel: '+ Superserie',
          onAddSuperset: () {},
        ),
      );

      final a =
          tester.getTopLeft(find.byKey(const Key('day_add_exercise_button')));
      final b = tester.getTopLeft(find.byKey(const Key('add_superset_button')));
      expect(a.dy, b.dy,
          reason: 'Antes estaban apilados en dos filas a ancho completo.');
    });

    testWidgets('sin superserie el botón de ejercicio toma el ancho completo',
        (tester) async {
      await _montar(
        tester,
        DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: () {},
        ),
      );

      expect(find.byKey(const Key('add_superset_button')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('day_add_exercise_button'))).width,
        400,
      );
    });

    testWidgets('a 320 px de ancho no desborda', (tester) async {
      // El criterio de aceptación de la épica #862 pide 320 px sin overflow.
      // El texto NO se mide acá: con GoogleFonts los tests caen a una fuente
      // de fallback que mide bastante más ancho que Barlow, así que lo que se
      // afirma es que no hay excepción de layout — los labels llevan ellipsis
      // justamente para que el ancho del texto deje de ser una variable.
      await _montar(
        tester,
        DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: () {},
          supersetLabel: '+ Superserie',
          onAddSuperset: () {},
        ),
        ancho: 320 - 28, // menos el padding horizontal del cuerpo del día
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('un botón sin callback queda inerte pero visible',
        (tester) async {
      await _montar(
        tester,
        const DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: null,
        ),
      );

      expect(find.byKey(const Key('day_add_exercise_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('semántica — los tres se anuncian como BOTÓN', () {
    // Regresión de #869: al cambiar `TextButton.icon` por `InkWell` se perdió
    // el rol de botón, y un lector de pantalla los leía como texto que se puede
    // tocar. El rol lo daba el widget de Material que estos reemplazan, así que
    // hay que reponerlo a mano.
    testWidgets('las dos acciones del día', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: () {},
          supersetLabel: '+ Superserie',
          onAddSuperset: () {},
        ),
      );

      expect(
        tester.getSemantics(_nodoDe(const Key('day_add_exercise_button'))),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          label: 'Agregar ejercicio',
        ),
      );
      expect(
        tester.getSemantics(_nodoDe(const Key('add_superset_button'))),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          label: '+ Superserie',
        ),
      );
      handle.dispose();
    });

    testWidgets('+ Agregar set', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        AddSetButton(
          key: const Key('add_set_button'),
          label: '+ Agregar set',
          onPressed: () {},
        ),
      );

      expect(
        tester.getSemantics(_nodoDe(const Key('add_set_button'))),
        matchesSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          label: '+ Agregar set',
        ),
      );
      handle.dispose();
    });

    testWidgets('un botón sin callback se anuncia deshabilitado',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        const DayActionButtons(
          exerciseLabel: 'Agregar ejercicio',
          onAddExercise: null,
        ),
      );

      expect(
        tester.getSemantics(_nodoDe(const Key('day_add_exercise_button'))),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          label: 'Agregar ejercicio',
        ),
        reason: 'Sin callback sigue siendo un botón, pero deshabilitado: no '
            'expone tap ni foco. Decirlo es la mitad del trabajo de la '
            'semántica.',
      );
      handle.dispose();
    });
  });

  group('AddSetButton — la acción de menor jerarquía', () {
    testWidgets('mide el mismo alto que las acciones del día', (tester) async {
      await _montar(
        tester,
        AddSetButton(
          key: const Key('add_set_button'),
          label: '+ Agregar set',
          onPressed: () {},
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('add_set_button'))).height,
        _kAltoEsperado,
        reason: 'El handoff pedía 44. La épica pide que ningún target quede '
            'por debajo de 48, y la jerarquía ya la carga el punteado.',
      );
    });

    testWidgets('toma el ancho completo y responde al tap', (tester) async {
      var tocado = false;
      await _montar(
        tester,
        AddSetButton(
          key: const Key('add_set_button'),
          label: '+ Agregar set',
          onPressed: () => tocado = true,
        ),
      );

      expect(
          tester.getSize(find.byKey(const Key('add_set_button'))).width, 400);
      await tester.tap(find.byKey(const Key('add_set_button')));
      await tester.pump();
      expect(tocado, isTrue);
    });
  });

  group('SupersetBlock — el bloque que antes no se veía', () {
    testWidgets('el encabezado dice cuántos ejercicios agrupa', (tester) async {
      await _montar(
        tester,
        const SupersetBlock(
          count: 2,
          children: [SizedBox(height: 40)],
        ),
      );

      expect(find.text('SUPERSERIE · 2 EJERCICIOS'), findsOneWidget);
    });

    testWidgets('con un solo ejercicio el plural no miente', (tester) async {
      await _montar(
        tester,
        const SupersetBlock(
          count: 1,
          children: [SizedBox(height: 40)],
        ),
      );

      expect(find.text('SUPERSERIE · 1 EJERCICIO'), findsOneWidget);
    });

    testWidgets('el trailing y el footer son opcionales', (tester) async {
      await _montar(
        tester,
        const SupersetBlock(count: 2, children: [SizedBox(height: 40)]),
      );
      expect(tester.takeException(), isNull);

      await _montar(
        tester,
        const SupersetBlock(
          count: 2,
          trailing: Icon(Icons.abc, key: Key('t')),
          footer: SizedBox(key: Key('f'), height: 20),
          children: [SizedBox(height: 40)],
        ),
      );
      expect(find.byKey(const Key('t')), findsOneWidget);
      expect(find.byKey(const Key('f')), findsOneWidget);
    });

    testWidgets('el encabezado se trunca en vez de desbordar', (tester) async {
      await _montar(
        tester,
        const SupersetBlock(count: 12, children: [SizedBox(height: 40)]),
        ancho: 140,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SupersetBadge — la marca de orden', () {
    testWidgets('numera desde A1, no desde A0', (tester) async {
      await _montar(
        tester,
        const Row(
          children: [
            SupersetBadge(position: 0),
            SupersetBadge(position: 1),
          ],
        ),
      );

      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      expect(find.text('A0'), findsNothing);
    });

    testWidgets('mide 22x22 en las dos paletas', (tester) async {
      // Envuelto en una Column con `mainAxisSize: min` porque es como vive en
      // el agarre de la card. Bajo constraints TIGHT un `Container(width:)` se
      // estira —es una preferencia, no un techo— y el badge saldría del ancho
      // del padre; montarlo suelto en un SizedBox mediría eso y no el badge.
      for (final tema in [AppTheme.dark(), AppTheme.light()]) {
        await _montar(
          tester,
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [SupersetBadge(position: 0)],
          ),
          tema: tema,
        );
        expect(tester.getSize(find.byType(SupersetBadge)), const Size(22, 22));
      }
    });
  });
}
