// La barra de accesorio del editor de rutina, aislada (#867).
//
// Unifica dos atajos que existían y nadie encontraba: los steppers de kilos,
// que sólo aparecían con foco en KG y sólo en esa fila, y el bulk-fill de
// columna, que era un tap sobre un header de 10,5 px con un ícono de 11.
//
// Estos tests son de widget aislado; el cableado con la tabla de series lo
// cubren `routine_editor_kg_steppers_test.dart` y
// `routine_editor_column_fill_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/keyboard_accessory_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

FocusedSetCell _celda({
  Object cellId = 'c1',
  String contexto = 'Press de banca · set 3 · kg',
  double paso = 2.5,
  String etiqueta = '2.5',
  bool puedeBajar = true,
  void Function(double)? onStep,
  VoidCallback? onFill,
  String subir = 'Sumar 2.5 kilos al peso',
  String bajar = 'Restar 2.5 kilos al peso',
}) =>
    FocusedSetCell(
      cellId: cellId,
      contextLabel: contexto,
      stepAmount: paso,
      stepLabel: etiqueta,
      canDecrease: puedeBajar,
      onStep: onStep ?? (_) {},
      stepIncreaseLabel: subir,
      stepDecreaseLabel: bajar,
      onFillColumn: onFill,
    );

Future<void> _montar(WidgetTester tester, Widget hijo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(bottomSheet: hijo),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _mas => find.byKey(const Key('accessory_step_plus'));
Finder get _menos => find.byKey(const Key('accessory_step_minus'));
Finder get _replicar => find.byKey(const Key('accessory_fill_column'));

void main() {
  group('steppers', () {
    testWidgets('el label del paso sale del dato, no del widget',
        (tester) async {
      await _montar(tester, KeyboardAccessoryBar(cell: _celda()));
      expect(find.text('+2.5'), findsOneWidget);
      expect(find.text('−2.5'), findsOneWidget);

      await _montar(
        tester,
        KeyboardAccessoryBar(cell: _celda(paso: 1, etiqueta: '1')),
      );
      expect(find.text('+1'), findsOneWidget,
          reason: 'en repeticiones el salto es de a 1');
      expect(find.text('−1'), findsOneWidget);
    });

    testWidgets('suman y restan el paso que les toca', (tester) async {
      final saltos = <double>[];
      await _montar(
        tester,
        KeyboardAccessoryBar(cell: _celda(onStep: saltos.add)),
      );

      await tester.tap(_mas);
      await tester.tap(_menos);
      expect(saltos, [2.5, -2.5]);
    });

    testWidgets('sin nada que restar, bajar queda inerte', (tester) async {
      final saltos = <double>[];
      await _montar(
        tester,
        KeyboardAccessoryBar(
          cell: _celda(puedeBajar: false, onStep: saltos.add),
        ),
      );

      expect(tester.widget<GestureDetector>(_menos).onTap, isNull);
      expect(tester.widget<GestureDetector>(_mas).onTap, isNotNull,
          reason: 'sumar sobre vacío sí tiene sentido: parte de 0');

      await tester.tap(_menos, warnIfMissed: false);
      expect(saltos, isEmpty);
    });

    testWidgets('se anuncian con qué mueven, no con el glifo', (tester) async {
      // Regresión: el nodo de Semantics expone sólo su texto —"−2.5", "+1"— y
      // el contexto vive en otro nodo más abajo. Sin label propio, un lector
      // de pantalla no distingue si el control mueve kilos, reps, el mínimo o
      // el máximo. Los steppers de peso ya traían estos labels.
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        KeyboardAccessoryBar(
          cell: _celda(
            paso: 1,
            etiqueta: '1',
            subir: 'Sumar 1 repeticiones',
            bajar: 'Restar 1 repeticiones',
          ),
        ),
      );

      expect(tester.getSemantics(_mas).label, 'Sumar 1 repeticiones');
      expect(tester.getSemantics(_menos).label, 'Restar 1 repeticiones');
      handle.dispose();
    });

    testWidgets('los dos miden 44 de alto', (tester) async {
      await _montar(tester, KeyboardAccessoryBar(cell: _celda()));
      expect(tester.getSize(_mas).height, 44);
      expect(tester.getSize(_menos).height, 44);
    });
  });

  group('A TODAS', () {
    testWidgets('no se dibuja cuando no hay dónde replicar', (tester) async {
      await _montar(tester, KeyboardAccessoryBar(cell: _celda()));
      expect(_replicar, findsNothing,
          reason: 'onFillColumn null = un ejercicio de un solo set');
    });

    testWidgets('con callback aparece y lo dispara', (tester) async {
      var toques = 0;
      await _montar(
        tester,
        KeyboardAccessoryBar(cell: _celda(onFill: () => toques++)),
      );

      expect(_replicar, findsOneWidget);
      expect(find.text('A TODAS'), findsOneWidget);
      await tester.tap(_replicar);
      expect(toques, 1);
    });

    testWidgets('tiene el mismo alto que los steppers', (tester) async {
      await _montar(
        tester,
        KeyboardAccessoryBar(cell: _celda(onFill: () {})),
      );
      expect(tester.getSize(_replicar).height, tester.getSize(_mas).height);
    });
  });

  group('contexto', () {
    testWidgets('dice sobre qué celda actúan los botones', (tester) async {
      await _montar(
        tester,
        KeyboardAccessoryBar(
          cell: _celda(contexto: 'Press militar · set 2 · reps'),
        ),
      );
      expect(find.text('Press militar · set 2 · reps'), findsOneWidget);
    });

    testWidgets('un nombre largo se trunca en vez de desbordar',
        (tester) async {
      await _montar(
        tester,
        KeyboardAccessoryBar(
          cell: _celda(contexto: 'Press ${'muy ' * 40}largo · set 1 · kg'),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FocusedCellNotifier', () {
    test('el blur de otra celda no borra la que tiene el foco', () {
      final n = FocusedCellNotifier();
      n.focus(_celda(cellId: 'a'));
      n.blur('b');
      expect(n.value?.cellId, 'a',
          reason: 'al saltar de celda, la nueva publica ANTES de que la vieja '
              'avise: sin el chequeo de identidad la barra parpadearía');
      n.blur('a');
      expect(n.value, isNull);
      n.dispose();
    });

    test('después de dispose no notifica en vez de tirar', () {
      final n = FocusedCellNotifier()..dispose();
      // Las filas sueltan el foco en un post-frame; para entonces la pantalla
      // puede haberse ido con el notifier ya dispuesto.
      expect(() => n.blur('a'), returnsNormally);
      expect(() => n.focus(_celda()), returnsNormally);
    });
  });

  group('KeyboardAccessorySlot', () {
    testWidgets('sin celda no ocupa alto', (tester) async {
      await _montar(tester, const KeyboardAccessorySlot(cell: null));
      expect(find.byType(KeyboardAccessoryBar), findsNothing);
    });

    testWidgets('con celda monta la barra', (tester) async {
      await _montar(tester, KeyboardAccessorySlot(cell: _celda()));
      expect(find.byType(KeyboardAccessoryBar), findsOneWidget);
    });
  });
}
