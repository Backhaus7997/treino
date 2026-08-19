import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/workout_clock.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';
import 'package:treino/features/workout/presentation/widgets/duration_set_row.dart';

import '../../../helpers/test_app_wrapper.dart';

void main() {
  /// Reloj de pared controlable. La fila lo lee en cada tick.
  late DateTime ahora;

  setUp(() {
    ahora = DateTime.utc(2027, 1, 15, 10);
  });

  Future<void> montar(
    WidgetTester tester, {
    required VoidCallback? onDone,
    int targetSeconds = 60,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutClockProvider.overrideWithValue(() => ahora),
        ],
        child: TestAppWrapper(
          child: DurationSetRow(
            setNumber: 2,
            targetSeconds: targetSeconds,
            isDone: false,
            onDone: onDone,
          ),
        ),
      ),
    );
  }

  Future<void> arrancar(WidgetTester tester) async {
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
  }

  testWidgets('antes de arrancar muestra el objetivo', (tester) async {
    await montar(tester, onDone: () {});
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Iniciar'), findsOneWidget);
  });

  testWidgets('la cuenta NO depende de cuántos ticks corrieron',
      (tester) async {
    // Este es el test que justifica el cambio entero.
    //
    // La fila contaba decrementando un contador una vez por tick. Con la app
    // estrangulada —pantalla bloqueada, batería baja, otra app adelante— los
    // ticks no corren y NO se recuperan: una plancha de 60 segundos terminaba
    // durando 70, y el atleta no tenía cómo notarlo.
    //
    // Acá se simula exactamente eso: pasan 70 segundos de RELOJ DE PARED y
    // corre UN SOLO tick. Con la implementación vieja el contador estaría en
    // 59 y la serie sin marcar.
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);
    expect(find.text('01:00'), findsOneWidget);

    ahora = ahora.add(const Duration(seconds: 70));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(marcada, isTrue,
        reason: 'la serie tiene que marcarse: el tiempo ya pasó');
    expect(find.text('00:00'), findsNothing,
        reason: 'terminada, vuelve a mostrar el objetivo');
  });

  testWidgets('mientras corre, la cuenta baja con el reloj de pared',
      (tester) async {
    await montar(tester, onDone: () {});
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    // Redondeo hacia ARRIBA: con una fracción de segundo por delante la serie
    // NO terminó. Mostrar 0 con tiempo restante invita a cortar antes.
    ahora = ahora.add(const Duration(milliseconds: 34600));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:01'), findsOneWidget);
  });

  testWidgets('cancelar corta la cuenta, no marca la serie, y avisa al reloj',
      (tester) async {
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget,
        reason: 'vuelve al objetivo, lista para arrancar de nuevo');
    expect(find.text('Iniciar'), findsOneWidget);

    // Y sobre todo: pasar el tiempo NO marca una serie cancelada.
    ahora = ahora.add(const Duration(seconds: 300));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(marcada, isFalse);
  });

  testWidgets('una fila no interactiva no arranca nada', (tester) async {
    await montar(tester, onDone: null);
    await tester.tap(find.text('Iniciar'));
    await tester.pump();

    ahora = ahora.add(const Duration(seconds: 120));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(find.text('01:00'), findsOneWidget);
  });
}
