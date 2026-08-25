import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/watch/presentation/wear/wear_exercise_timer_screen.dart';
import 'package:treino/features/watch/presentation/wear/wear_strings.dart';
import 'package:treino/features/watch/presentation/wear/wear_widgets.dart';

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

  /// El lado del viewport en dp, que en un reloj redondo es también el diámetro.
  double lado(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio;

  testWidgets('los dos botones entran ENTEROS sin girar la corona',
      (tester) async {
    // El defecto: el contenido no entraba en el viewport de 206,1 dp y la fila
    // de botones terminaba en y=267. Se llegaba con la corona, pero de entrada
    // se veía media píldora cortada contra el borde. Ahora va de 147,5 a 195,5.
    //
    // «Entero» se mide sobre la píldora, no sobre la etiqueta: lo que se veía
    // cortado era el borde del botón.
    await montar(tester);

    final alto = lado(tester);
    for (var i = 0; i < 2; i++) {
      final boton = tester.getRect(find.byType(WearButton).at(i));
      expect(
        boton.bottom,
        lessThanOrEqualTo(alto),
        reason: 'el botón $i termina en ${boton.bottom} y la pantalla en $alto',
      );
      expect(boton.top, greaterThanOrEqualTo(0));
    }
  });

  testWidgets('las etiquetas quedan dentro del CÍRCULO de la pantalla',
      (tester) async {
    // Que entren en el rectángulo no alcanza: la pantalla es REDONDA. A la
    // altura donde estaban los botones la cuerda visible terminaba en x=156 y
    // «Cancelar» llegaba hasta x=176 — de ahí el «Cancela» del reporte, con la
    // «r» comida por el bisel.
    //
    // Se miden los extremos a la altura MEDIA de la etiqueta y no las esquinas
    // de su caja: la caja de un texto incluye el hueco de los descendentes, así
    // que sus esquinas caen más abajo que cualquier glifo real. Medir ahí
    // reprobaría un texto que se lee perfecto.
    //
    // La píldora entera NO entra en el círculo, y no es un ajuste pendiente: con
    // dos botones a lo ancho las esquinas externas caen fuera a cualquier altura
    // que deje lugar para el anillo. Lo que se garantiza es que el corte pase
    // por el borde del botón y nunca por la mitad de una palabra.
    await montar(tester);

    final diametro = lado(tester);
    final centro = Offset(diametro / 2, diametro / 2);
    final radio = diametro / 2;

    for (final etiqueta in ['Ocultar', 'Cancelar']) {
      final caja = tester.getRect(find.text(etiqueta));
      for (final borde in [
        Offset(caja.left, caja.center.dy),
        Offset(caja.right, caja.center.dy),
      ]) {
        expect(
          (borde - centro).distance,
          lessThanOrEqualTo(radio),
          reason: '«$etiqueta» se sale del círculo en $borde '
              '(a ${(borde - centro).distance} del centro, radio $radio)',
        );
      }
    }
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

  testWidgets('con calorías pero sin pulso todavía, el pulso NO desaparece',
      (tester) async {
    // Los dos sensores no llegan juntos: las calorías aparecen enseguida y el
    // pulso unos segundos más tarde. En esa ventana la fila dibujaba sólo
    // `🔥 0 kcal`, sin corazón, y en la muñeca eso se lee como «este reloj no
    // mide el pulso» en vez de «el sensor está calentando».
    //
    // El caso «sin ninguna medición» ya estaba cubierto arriba, y pasaba: el
    // placeholder colgaba de `effort.isEmpty`, o sea de la fila ENTERA. La
    // medición PARCIAL no entraba por ese camino.
    await montar(tester, effort: const WatchEffortDisplay(kcal: 0));

    expect(find.text('--'), findsOneWidget);
    expect(find.text(WearStrings.bpmUnit), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text(WearStrings.kcalUnit), findsOneWidget);
  });
}
