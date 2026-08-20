import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/watch/presentation/wear/wear_exercise_timer_screen.dart';

/// Renderiza la pantalla del temporizador EN EL TAMAÑO REAL del reloj.
///
/// ## Por qué existe este archivo
///
/// Casi todos los defectos de esta pantalla fueron de LAYOUT, y todos se vieron
/// primero en la muñeca: el anillo saliendo elíptico porque un `ListView`
/// impone ancho completo, el botón cortado contra el borde, «Cancelar» pegado a
/// la izquierda. Ninguno necesitaba un reloj para detectarse — necesitaban
/// dibujar en 206 dp y mirar.
///
/// Flutter lanza excepción ante un overflow, así que basta con montar la
/// pantalla en el tamaño del SM-L500 para que un desborde rompa el test.
void main() {
  /// Samsung SM-L500: 438 px físicos, densidad 2.125 → 206 dp de lado.
  const fisico = Size(438, 438);
  const densidad = 2.125;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = fisico;
    view.devicePixelRatio = densidad;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  WearExerciseTimer timer({
    int remainingMs = 20000,
    int totalMs = 45000,
    bool finished = false,
  }) =>
      (
        endsAtElapsedMs: 100000,
        totalMs: totalMs,
        remainingMs: remainingMs,
        finished: finished,
      );

  Future<void> montar(
    WidgetTester tester, {
    String nombre = 'abdominales en v',
    WearExerciseTimer? t,
    WatchEffortDisplay effort = const WatchEffortDisplay.nada(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.mintMagenta]),
          home: WearExerciseTimerScreen(
            exerciseName: nombre,
            timer: t ?? timer(),
            effort: effort,
            onOcultar: () {},
            onCancelar: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('entra en la pantalla del reloj sin desbordar', (tester) async {
    // Si algo se sale, Flutter tira y el test falla. Es exactamente el defecto
    // que hubo que descubrir mirando la muñeca tres veces seguidas.
    await montar(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('un nombre LARGO tampoco desborda', (tester) async {
    await montar(
      tester,
      nombre: 'movilidad de hombros rotación interna por espalda con baston',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('el anillo es REDONDO, no una elipse', (tester) async {
    // El bug: dentro de un `ListView` los hijos reciben ancho completo, así que
    // el `SizedBox` se ignoraba y el indicador se estiraba a lo ancho.
    await montar(tester);

    final caja = tester.getSize(
      find.byType(CircularProgressIndicator).first,
    );

    expect(caja.width, caja.height);
  });

  testWidgets('muestra el tiempo en MM:SS, igual que el teléfono',
      (tester) async {
    await montar(tester, t: timer(remainingMs: 20000));

    // 20 s → 00:20. Mismo formato en los dos aparatos: el atleta mira uno y
    // otro durante la misma serie.
    expect(find.text('00:20'), findsOneWidget);
  });

  testWidgets('redondea hacia ARRIBA el último segundo', (tester) async {
    // Con 200 ms restantes todavía falta: mostrar 00:00 haría pensar que
    // terminó.
    await montar(tester, t: timer(remainingMs: 200));

    expect(find.text('00:01'), findsOneWidget);
  });

  testWidgets('NO hay botón de marcar: al vencer se marca solo',
      (tester) async {
    await montar(tester, t: timer(remainingMs: 0, finished: true));

    expect(find.text('Marcar serie'), findsNothing);
  });

  testWidgets('ofrece ocultar y cancelar', (tester) async {
    await montar(tester);

    expect(find.text('Ocultar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('sin medición todavía, muestra guiones en vez de nada',
      (tester) async {
    // La fila oculta hacía pensar que el reloj no estaba midiendo, sobre todo
    // entrando desde el teléfono, donde la pantalla aparece antes del primer
    // dato de Health Services.
    await montar(tester);

    expect(find.text('--'), findsNWidgets(2));
  });

  testWidgets('con medición, muestra pulso y calorías', (tester) async {
    await montar(
      tester,
      effort: const WatchEffortDisplay(bpm: 118, kcal: 8),
    );

    expect(find.text('118'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });
}
