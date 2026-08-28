import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
