import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_time_grid.dart';

/// La grilla de tiempo del calendario — el modelo de Google Calendar y Teams.
///
/// La agenda usaba `TableCalendar`, que es un SELECTOR DE FECHAS: una
/// cuadrícula de días donde cada día es una celda igual a las demás. Ahí una
/// sesión de 20 minutos y una de tres horas se ven idénticas, y un hueco libre
/// no se ve en absoluto.
///
/// En una grilla de tiempo el eje vertical ES el reloj: la posición dice
/// cuándo, y el alto dice cuánto. Eso es lo que hace que se pueda mirar una
/// semana y entender de un vistazo dónde entra alguien.
void main() {
  final lunes = DateTime(2026, 9, 7); // ISO weekday 1

  AgendaEvent evento(
    String id,
    DateTime desde,
    int minutos, {
    String titulo = 'Sesión',
  }) =>
      AgendaEvent(
        id: id,
        startsAt: desde,
        durationMin: minutos,
        title: titulo,
      );

  Future<void> pump(
    WidgetTester tester, {
    required List<AgendaEvent> eventos,
    List<AgendaAvailabilityBand> bandas = const [],
    DateTime? ahora,
    void Function(DateTime)? onHueco,
    int dias = 1,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: AgendaTimeGrid(
          firstDay: lunes,
          dayCount: dias,
          events: eventos,
          availability: bandas,
          now: ahora,
          onEmptySlotTap: onHueco,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('El eje vertical es el reloj —', () {
    testWidgets('el alto de una sesión es proporcional a lo que dura',
        (tester) async {
      await pump(tester, eventos: [
        evento('a', DateTime(2026, 9, 7, 9), 30),
        evento('b', DateTime(2026, 9, 7, 11), 90),
      ]);

      final corta = tester.getSize(find.byKey(const Key('agenda_event_a')));
      final larga = tester.getSize(find.byKey(const Key('agenda_event_b')));

      expect(larga.height / corta.height, moreOrLessEquals(3.0, epsilon: 0.15),
          reason: '90 minutos tienen que medir el triple que 30');
    });

    testWidgets('la posición vertical dice a qué hora empieza', (tester) async {
      await pump(tester, eventos: [
        evento('temprano', DateTime(2026, 9, 7, 9), 60),
        evento('tarde', DateTime(2026, 9, 7, 17), 60),
      ]);

      final y1 = tester.getTopLeft(find.byKey(const Key('agenda_event_temprano'))).dy;
      final y2 = tester.getTopLeft(find.byKey(const Key('agenda_event_tarde'))).dy;

      expect(y2, greaterThan(y1));
    });
  });

  group('Solapamiento —', () {
    testWidgets('dos sesiones a la misma hora se reparten el ancho, no se '
        'tapan', (tester) async {
      await pump(tester, eventos: [
        evento('x', DateTime(2026, 9, 7, 10), 60),
        evento('y', DateTime(2026, 9, 7, 10, 30), 60),
      ]);

      final a = tester.getRect(find.byKey(const Key('agenda_event_x')));
      final b = tester.getRect(find.byKey(const Key('agenda_event_y')));

      // Se solapan en el tiempo, así que NO pueden ocupar la misma columna.
      final seTapan = a.left < b.right && b.left < a.right;
      expect(seTapan, isFalse,
          reason: 'encimadas, una esconde a la otra y el PF no la ve');
    });

    testWidgets('dos que no se tocan usan el ancho completo', (tester) async {
      await pump(tester, eventos: [
        evento('m', DateTime(2026, 9, 7, 9), 60),
        evento('t', DateTime(2026, 9, 7, 15), 60),
      ]);

      final a = tester.getSize(find.byKey(const Key('agenda_event_m')));
      final b = tester.getSize(find.byKey(const Key('agenda_event_t')));
      expect(a.width, moreOrLessEquals(b.width, epsilon: 0.5));
    });
  });

  group('Disponibilidad de fondo —', () {
    testWidgets('la banda se pinta donde el PF dijo que atiende',
        (tester) async {
      await pump(
        tester,
        eventos: const [],
        bandas: const [
          AgendaAvailabilityBand(weekday: 1, startMinute: 540, endMinute: 720),
        ],
      );

      expect(find.byKey(const Key('agenda_band_1_540')), findsOneWidget);
    });

    testWidgets('sin reglas para ese día no hay banda', (tester) async {
      await pump(
        tester,
        eventos: const [],
        bandas: const [
          // Martes (2), pero la grilla arranca lunes y muestra 1 día.
          AgendaAvailabilityBand(weekday: 2, startMinute: 540, endMinute: 720),
        ],
      );

      expect(find.byKey(const Key('agenda_band_2_540')), findsNothing);
    });
  });

  group('La línea de ahora —', () {
    testWidgets('aparece si hoy está en el rango visible', (tester) async {
      await pump(
        tester,
        eventos: [evento('a', DateTime(2026, 9, 7, 10), 60)],
        ahora: DateTime(2026, 9, 7, 11, 30),
      );

      expect(find.byKey(const Key('agenda_now_line')), findsOneWidget);
    });

    testWidgets('no aparece si la semana mostrada es otra', (tester) async {
      await pump(
        tester,
        eventos: [evento('a', DateTime(2026, 9, 7, 10), 60)],
        ahora: DateTime(2026, 12, 25, 11, 30),
      );

      expect(find.byKey(const Key('agenda_now_line')), findsNothing);
    });
  });

  group('Crear tocando un hueco —', () {
    testWidgets('devuelve el día y la hora del punto tocado', (tester) async {
      DateTime? tocado;
      await pump(
        tester,
        eventos: const [],
        bandas: const [
          AgendaAvailabilityBand(weekday: 1, startMinute: 540, endMinute: 1020),
        ],
        onHueco: (d) => tocado = d,
      );

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('agenda_day_column_0'))),
      );
      await tester.pumpAndSettle();

      expect(tocado, isNotNull,
          reason: 'tocar un hueco tiene que poder crear una sesión ahí');
      expect(tocado!.day, 7);
      expect(tocado!.minute % 15, 0,
          reason: 'se redondea al cuarto de hora, como Google Calendar');
    });
  });

  group('Encabezado de días —', () {
    testWidgets('cada columna dice qué día es', (tester) async {
      await pump(tester, eventos: const [], dias: 7);

      // Sin esto la grilla es ilegible: siete columnas idénticas y ninguna
      // manera de saber cuál es martes.
      expect(find.text('7'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
      expect(find.textContaining('LUN'), findsOneWidget);
      expect(find.textContaining('DOM'), findsOneWidget);
    });

    testWidgets('hoy se distingue del resto', (tester) async {
      await pump(
        tester,
        eventos: const [],
        dias: 7,
        ahora: DateTime(2026, 9, 9, 12),
      );

      expect(find.byKey(const Key('agenda_header_today')), findsOneWidget);
    });

    testWidgets('sin hoy en el rango, ningún día queda marcado',
        (tester) async {
      await pump(
        tester,
        eventos: const [],
        dias: 7,
        ahora: DateTime(2026, 12, 25, 12),
      );

      expect(find.byKey(const Key('agenda_header_today')), findsNothing);
    });
  });

  group('Llenar el alto —', () {
    // Reportado mirando el Coach Hub: con disponibilidad de 9 a 11 y ninguna
    // sesión, la grilla medía 224 px adentro de un panel de 700 y abajo
    // quedaba un vacío enorme. Se veía CORTADA A LA MITAD — porque lo estaba.
    //
    // El primer arreglo estiraba el RANGO hasta llenar el panel, y eso trajo
    // el bug siguiente: sin sobrante no había scroll, y las horas fuera del
    // rango quedaban inalcanzables. Ahora se dibuja el día ENTERO, que llena
    // cualquier panel y además se puede recorrer. Este test sigue siendo el
    // que impide volver a la franja de 224 px.
    testWidgets('nunca se dibuja en una franja: el día entero llena el panel',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: AgendaTimeGrid(
              firstDay: lunes,
              dayCount: 7,
              events: [evento('a', DateTime(2026, 9, 7, 10), 60)],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final columna =
          tester.getSize(find.byKey(const Key('agenda_day_column_0')));

      // Sin el arreglo la columna mide (12-9)*56 = 168 px y el resto es vacío.
      expect(columna.height, greaterThan(500),
          reason: 'la grilla tiene que ocupar el panel, no una franja');
    });

    testWidgets('si el alto no alcanza, se scrollea', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: AgendaTimeGrid(
              firstDay: lunes,
              dayCount: 7,
              events: [
                evento('a', DateTime(2026, 9, 7, 7), 60),
                evento('b', DateTime(2026, 9, 7, 22), 60),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('Todas las horas son alcanzables —', () {
    // Reportado mirando el Coach Hub: "no tiene scroll el calendario, no
    // puedo mover las horas".
    //
    // El arreglo anterior estiraba el RANGO hasta llenar el panel. Con eso la
    // grilla dejaba de tener sobrante, así que dejaba de scrollear — y las
    // horas fuera del rango quedaban INALCANZABLES. Se cambió un vacío por
    // una jaula.
    //
    // El día entero se dibuja siempre. Que no tengas que mirar las 3 de la
    // mañana se resuelve abriendo POSICIONADO donde está el contenido, no
    // recortando lo que existe.
    testWidgets('el día entero está en la grilla, de 00 a 23', (tester) async {
      await pump(tester, eventos: [
        evento('a', DateTime(2026, 9, 7, 10), 60),
      ]);

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('y se puede scrollear', (tester) async {
      await pump(tester, eventos: [
        evento('a', DateTime(2026, 9, 7, 10), 60),
      ]);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.controller, isNotNull,
          reason: 'hace falta controlar la posición para abrir donde importa');
      expect(scroll.controller!.position.maxScrollExtent, greaterThan(0),
          reason: 'sin sobrante no hay scroll, y el resto del día queda '
              'inalcanzable');
    });

    testWidgets('abre posicionada en el contenido, no a la medianoche',
        (tester) async {
      await pump(tester, eventos: [
        evento('a', DateTime(2026, 9, 7, 14), 60),
      ]);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.controller!.offset, greaterThan(0),
          reason: 'abrir a las 00:00 con la primera sesión a las 14 obliga a '
              'scrollear en cada apertura');
    });
  });

  group('Bandas contiguas —', () {
    testWidgets('dos franjas pegadas se dibujan como UNA', (tester) async {
      await pump(
        tester,
        eventos: const [],
        bandas: const [
          AgendaAvailabilityBand(weekday: 1, startMinute: 540, endMinute: 600),
          AgendaAvailabilityBand(weekday: 1, startMinute: 600, endMinute: 660),
        ],
      );

      // Dos cajas pegadas dejan una costura visible y se leen como dos cosas
      // distintas. De 9 a 11 sin corte es UN bloque de disponibilidad.
      expect(find.byKey(const Key('agenda_band_1_540')), findsOneWidget);
      expect(find.byKey(const Key('agenda_band_1_600')), findsNothing);

      final banda = tester.getSize(find.byKey(const Key('agenda_band_1_540')));
      final unaHora = tester.getSize(
            find.byKey(const Key('agenda_day_column_0')),
          ).height /
          24;
      expect(banda.height, moreOrLessEquals(unaHora * 2, epsilon: 2),
          reason: 'la banda fusionada tiene que medir las dos horas');
    });

    testWidgets('dos franjas separadas siguen siendo dos', (tester) async {
      await pump(
        tester,
        eventos: const [],
        bandas: const [
          AgendaAvailabilityBand(weekday: 1, startMinute: 540, endMinute: 660),
          AgendaAvailabilityBand(weekday: 1, startMinute: 900, endMinute: 1020),
        ],
      );

      expect(find.byKey(const Key('agenda_band_1_540')), findsOneWidget);
      expect(find.byKey(const Key('agenda_band_1_900')), findsOneWidget);
    });
  });
}
