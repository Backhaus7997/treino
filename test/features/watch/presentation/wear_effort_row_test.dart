import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/watch/presentation/wear/wear_strings.dart';
import 'package:treino/features/watch/presentation/wear/wear_widgets.dart';

/// La fila de esfuerzo, con las DOS políticas de placeholder que conviven.
///
/// ## Por qué merece un archivo propio
///
/// `WearEffortRow` la usan dos pantallas con reglas OPUESTAS: la lista de series
/// esconde lo que no midió, y el temporizador reserva el lugar con guiones. El
/// bug de la medición parcial nació de resolver esa decisión para la fila entera
/// en vez de por métrica, así que las dos políticas necesitan quedar clavadas —
/// arreglar una sin romper la otra es exactamente el riesgo.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required WatchEffortDisplay effort,
    required bool mostrarSinDatos,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.mintMagenta]),
        home: Scaffold(
          body: Center(
            child: WearEffortRow(
              effort: effort,
              mostrarSinDatos: mostrarSinDatos,
            ),
          ),
        ),
      ),
    );
  }

  group('con placeholder — la pantalla del ejercicio por tiempo', () {
    testWidgets('sin ninguna medición, reserva las dos métricas',
        (tester) async {
      await montar(
        tester,
        effort: const WatchEffortDisplay.nada(),
        mostrarSinDatos: true,
      );

      expect(find.text('--'), findsNWidgets(2));
      expect(find.text(WearStrings.bpmUnit), findsOneWidget);
      expect(find.text(WearStrings.kcalUnit), findsOneWidget);
    });

    testWidgets('con calorías pero sin pulso, el pulso queda en guiones',
        (tester) async {
      // El caso del bug. Health Services entrega las calorías enseguida y el
      // pulso unos segundos más tarde: en esa ventana la fila dibujaba sólo
      // `🔥 0 kcal`, que en la muñeca se lee como "este reloj no mide el pulso".
      await montar(
        tester,
        effort: const WatchEffortDisplay(kcal: 0),
        mostrarSinDatos: true,
      );

      expect(find.text('--'), findsOneWidget);
      expect(find.text(WearStrings.bpmUnit), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text(WearStrings.kcalUnit), findsOneWidget);
    });

    testWidgets('con pulso pero sin calorías, las calorías quedan en guiones',
        (tester) async {
      // La simétrica. No es teórica: el permiso de calorías se puede negar sin
      // negar el de pulso, y ahí la fila se queda así indefinidamente.
      await montar(
        tester,
        effort: const WatchEffortDisplay(bpm: 118),
        mostrarSinDatos: true,
      );

      expect(find.text('118'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
      expect(find.text(WearStrings.kcalUnit), findsOneWidget);
    });

    testWidgets('con las dos mediciones no queda ningún guión', (tester) async {
      await montar(
        tester,
        effort: const WatchEffortDisplay(bpm: 118, kcal: 8),
        mostrarSinDatos: true,
      );

      expect(find.text('118'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('--'), findsNothing);
    });
  });

  group('sin placeholder — la lista de series', () {
    testWidgets('sin ninguna medición no dibuja nada', (tester) async {
      await montar(
        tester,
        effort: const WatchEffortDisplay.nada(),
        mostrarSinDatos: false,
      );

      expect(find.text('--'), findsNothing);
      expect(find.text(WearStrings.bpmUnit), findsNothing);
      expect(find.text(WearStrings.kcalUnit), findsNothing);
    });

    testWidgets('con medición parcial NO reserva el hueco de la que falta',
        (tester) async {
      // El guard del alcance. Acá reservar el lugar hace saltar el layout al
      // llegar el primer pulso, justo cuando el atleta está mirando los
      // círculos para marcar. La corrección de la medición parcial vale para el
      // temporizador y NO tiene que derramarse hasta acá.
      await montar(
        tester,
        effort: const WatchEffortDisplay(kcal: 8),
        mostrarSinDatos: false,
      );

      expect(find.text('8'), findsOneWidget);
      expect(find.text(WearStrings.kcalUnit), findsOneWidget);
      expect(find.text('--'), findsNothing);
      expect(find.text(WearStrings.bpmUnit), findsNothing);
    });
  });
}
