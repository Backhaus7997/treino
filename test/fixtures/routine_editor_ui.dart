import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/widgets/day_tab_bar.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';

/// Despliega todas las cards de ejercicio del editor de rutina.
///
/// Desde el rediseño de la card (#864) un ejercicio arranca **colapsado**
/// salvo que tenga sets inválidos: la tabla de series no está en el árbol
/// hasta que alguien toca la cabecera.
///
/// Sin esto, un `find.text('8')` sobre un valor de set devuelve cero y el
/// mensaje de error no dice por qué —"Found 0 widgets"— así que el test
/// parece roto cuando en realidad está mirando una card cerrada.
///
/// Solo abre las que estén cerradas: tocar la cabecera es un toggle, y una
/// card con error nace abierta. Tapear a ciegas la cerraría.
Future<void> expandirEjercicios(WidgetTester tester) async {
  const cuerpo = Key('exercise_card_body');
  const cabecera = Key('exercise_card_header');

  // Tope defensivo: si algo impide que una card abra, mejor cortar que
  // colgar el test en un loop infinito.
  for (var vuelta = 0; vuelta < 30; vuelta++) {
    final cards = find.byType(ExerciseCard);
    final total = cards.evaluate().length;
    if (total == 0) return;

    var abrioAlguna = false;
    for (var i = 0; i < total; i++) {
      final card = cards.at(i);
      final yaAbierta = find
          .descendant(of: card, matching: find.byKey(cuerpo))
          .evaluate()
          .isNotEmpty;
      if (yaAbierta) continue;

      final tap = find.descendant(of: card, matching: find.byKey(cabecera));
      if (tap.evaluate().isEmpty) continue;
      await tester.ensureVisible(tap);
      await tester.pumpAndSettle();
      await tester.tap(tap, warnIfMissed: false);
      await tester.pumpAndSettle();
      abrioAlguna = true;
      break; // el árbol cambió: volver a evaluar desde cero
    }
    if (!abrioAlguna) return;
  }
}

/// Selecciona la pestaña del día [indice] (0-based) y deja sus cards abiertas.
///
/// Desde el rediseño (#865) el editor renderiza **un día a la vez**. Un test
/// que busque contenido del día 2 sin tocar su pestaña encuentra cero widgets,
/// y el mensaje —"Found 0 widgets"— no dice que el problema es de navegación.
///
/// Devuelve `false` si esa pestaña no existe, para que el test pueda afirmar
/// sobre eso en vez de fallar con un error de finder.
Future<bool> seleccionarDia(WidgetTester tester, int indice) async {
  final tab = find.byKey(Key('day_tab_$indice'));
  if (tab.evaluate().isEmpty) return false;
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab, warnIfMissed: false);
  await tester.pumpAndSettle();
  await expandirEjercicios(tester);
  return true;
}

/// Cuántos días tiene el editor, contando pestañas.
int cantidadDeDias(WidgetTester tester) =>
    tester.widgetList<DayTabBar>(find.byType(DayTabBar)).isEmpty
        ? 0
        : tester.widget<DayTabBar>(find.byType(DayTabBar)).labels.length;

/// Trae [objetivo] a la vista, scrolleando el ListView vertical del editor.
///
/// `ensureVisible` no alcanza: un `ListView` sólo construye los hijos visibles,
/// así que un widget que quedó abajo del pliegue **no está en el árbol** y el
/// finder devuelve cero antes de que nadie pueda scrollear hacia él.
///
/// Hizo falta a partir de #865: las pestañas de día y el estado vacío suman
/// alto, y en el viewport de 800x600 de los tests eso empuja los botones de
/// acción del día fuera de la ventana.
Future<void> desplazarHasta(WidgetTester tester, Finder objetivo) async {
  if (objetivo.evaluate().isNotEmpty) {
    await tester.ensureVisible(objetivo);
    await tester.pumpAndSettle();
    return;
  }
  // El editor tiene DOS scrollables: la barra de pestañas (horizontal) y el
  // contenido (vertical). Hay que nombrar el vertical o se scrollea el otro.
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  final candidato = vertical.evaluate().isNotEmpty
      ? vertical.first
      : (find.byType(Scrollable).evaluate().isNotEmpty
          ? find.byType(Scrollable).last
          : null);
  // Sin scrollable no hay nada que hacer: que falle el expect del test, con su
  // mensaje, en vez de reventar acá con un "Bad state: No element" que no dice
  // nada sobre lo que el test quería comprobar.
  if (candidato == null) return;
  try {
    await tester.scrollUntilVisible(objetivo, 150, scrollable: candidato);
  } on StateError {
    // Se acabó el scroll y el objetivo no apareció. Mismo criterio.
    return;
  }
  await tester.pumpAndSettle();
}

/// Atajo para el caso más común: el botón "Agregar ejercicio" del día visible.
Future<void> desplazarHastaAgregarEjercicio(
  WidgetTester tester, {
  String label = 'Agregar ejercicio',
}) =>
    desplazarHasta(tester, find.text(label));

/// Le da al test un viewport con alto de teléfono real.
///
/// `flutter_test` monta 800x600 por defecto. Un iPhone 16 son 402x874: el
/// editor de rutina entra cómodo en el segundo y no en el primero. Con 600 de
/// alto, la barra de pestañas más el estado vacío más la tabla de series
/// empujan los botones de acción fuera de la ventana, y como un `ListView`
/// sólo construye lo visible, esos widgets **no existen en el árbol** — el
/// finder devuelve cero y el test parece roto por otra cosa.
///
/// Se mantiene el ancho de 800 a propósito: cambiarlo movería layouts que
/// otros tests ya afirman.
void usarViewportAlto(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Abre la hoja "DATOS DEL PLAN" si no está abierta ya.
///
/// Desde #866 los objetivos, el nivel, el toggle de compartir y las semanas
/// viven detrás del engranaje del app bar: son ajustes que se setean una vez y
/// antes ocupaban el tercio superior del scroll. Un test que toque cualquiera
/// de esos controles tiene que abrir la hoja primero.
///
/// El nombre y el split NO están acá: se quedaron en la pantalla porque el
/// nombre es el único campo obligatorio y esconderlo dejaría una rutina nueva
/// sin ningún lugar visible donde escribirlo.
///
/// Es idempotente: llamarla dos veces no abre dos hojas.
Future<void> abrirDatosDelPlan(WidgetTester tester) async {
  if (find.byKey(const Key('plan_sheet_close')).evaluate().isNotEmpty) return;
  final boton = find.byKey(const Key('plan_sheet_button'));
  if (boton.evaluate().isEmpty) return;
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

/// Cierra la hoja "DATOS DEL PLAN" si está abierta.
///
/// Hace falta cuando el test sigue interactuando con la pantalla: la hoja es
/// modal y tapa todo lo de abajo.
Future<void> cerrarDatosDelPlan(WidgetTester tester) async {
  final cerrar = find.byKey(const Key('plan_sheet_close'));
  if (cerrar.evaluate().isEmpty) return;
  await tester.tap(cerrar);
  await tester.pumpAndSettle();
}

/// Simula que el teclado del sistema está arriba.
///
/// Hace falta desde #867: la barra de accesorio es un accesorio DEL TECLADO y
/// sólo se monta cuando `viewInsets.bottom > 0`. El foco solo no alcanza —
/// `enterText` enfoca un campo sin abrir ningún teclado—, y esa distinción es
/// deliberada: sin ella la barra se dibujaba también en los tests que sólo
/// tipean, y como el `bottomSheet` se superpone al body en vez de achicarlo,
/// tapaba el botón de guardar de veinte tests que no tenían nada que ver.
///
/// `viewInsets` va en píxeles FÍSICOS, de ahí la multiplicación por el dpr.
void simularTeclado(WidgetTester tester, {double alto = 300}) {
  final dpr = tester.view.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: alto * dpr);
  addTearDown(tester.view.reset);
}

/// Enfoca la celda de set [celda] con el teclado simulado, de modo que la
/// barra de accesorio quede en el árbol.
///
/// `tap` y no `enterText`: lo que publica la celda en el scope es el cambio de
/// foco, y hay que pasar por el gesto para que el `FocusNode` lo reciba.
Future<void> enfocarCelda(WidgetTester tester, Finder celda) async {
  simularTeclado(tester);
  await tester.ensureVisible(celda);
  await tester.pumpAndSettle();
  await tester.tap(celda);
  await tester.pumpAndSettle();
}

/// Las celdas de la tabla de series que llevan [hint] ('kg', 'reps', 'mín',
/// 'máx'). Son los únicos campos del editor con esos hints.
Finder celdasConHint(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
