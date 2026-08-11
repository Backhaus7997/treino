// PR-C — AgendaWebWeekGrid (grilla semanal de la Agenda web).
//
// El test de UBICACIÓN del bloque mide el top del bloque contra la etiqueta
// horaria de la canaleta. Es una buena red de geometría, pero OJO: NO es la
// red del `.toLocal()` de ADR-7. Los fixtures se arman con `DateTime.utc(...)`
// y `DateTime.utc(x).toLocal()` es la identidad cuando el proceso corre en UTC
// — que es exactamente lo que hace un runner de GitHub Actions (ci.yml no fija
// TZ). En ART falla; en CI pasaría igual. La red REAL de ADR-7 es el grupo
// "ADR-7 — sin .toLocal()" del final del archivo: escanea el fuente y es
// independiente del huso en el que corra la suite.
//
// Todas las strings son español hardcodeado + comentario // i18n (C-6) —
// mismo contrato que el widget bajo test. Sin AppL10n en este archivo.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_week_grid.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/new_session_dialog.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/week_grid_geometry.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

// ─── Constantes y fixtures ────────────────────────────────────────────────────

const _kTrainerId = 'trainer-week-grid';
const _kAthleteA = 'athlete-week-a';
const _kAthleteB = 'athlete-week-b';
const _kAthleteC = 'athlete-week-c';

const _kNameA = 'Ana López'; // i18n
const _kNameB = 'Bruno Díaz'; // i18n
const _kNameC = 'Caro Ruiz'; // i18n

/// La semana bajo test es la ACTUAL: la columna de hoy y la línea de ahora se
/// derivan de `argentinaNow()`, así que anclar en otra semana los apagaría.
final _kWeekStart = weekStartFor(argentinaNow());

/// Miércoles de la semana actual — la columna del medio (índice 2).
const _kColIdx = 2;

DateTime _dayAt(int idx) => _kWeekStart.add(Duration(days: idx));

/// Wall-clock UTC con precisión de minuto (ADR-7).
DateTime _at(int dayIdx, int hour, int minute) {
  final d = _dayAt(dayIdx);
  return DateTime.utc(d.year, d.month, d.day, hour, minute);
}

Appointment _appt({
  required String id,
  required DateTime startsAt,
  int durationMin = 60,
  String athleteId = _kAthleteA,
  String athleteName = _kNameA,
}) =>
    Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteName,
      startsAt: startsAt,
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
    );

// ─── Harness ──────────────────────────────────────────────────────────────────

/// Setea el viewport lógico. El `devicePixelRatio = 1.0` NO es opcional: sin
/// él, 1280×900 físicos son 426×300 lógicos y el test ejercita en silencio
/// otro layout. Copiado de coach_hub_scaffold_test.dart.
void _setViewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Overrides de todos los providers que toca la grilla (y los diálogos que
/// abre). El override de `trainerAppointmentsStreamProvider` es FAMILY-WIDE
/// (closure de dos argumentos): un override por key exacta es imposible
/// porque la ventana rodante se deriva de `DateTime.now()`.
List<Override> _overrides({
  Stream<List<Appointment>>? stream,
  List<Appointment> appointments = const [],
}) =>
    [
      currentUidProvider.overrideWithValue(_kTrainerId),
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => stream ?? Stream.value(appointments),
      ),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(const <TrainerLink>[]),
      ),
      for (final id in [_kAthleteA, _kAthleteB, _kAthleteC])
        userPublicProfileProvider(id).overrideWith((ref) => Stream.value(null)),
      // AppointmentDetailDialog (el que abre un bloque al tocarlo) precalienta
      // la tarifa de referencia del alumno.
      for (final id in [_kAthleteA, _kAthleteB, _kAthleteC])
        athleteBillingProvider(id).overrideWith(
          (ref) => Stream<AthleteBilling?>.value(null),
        ),
    ];

DateTime? _lastDayTapped;

/// El shell (CoachHubScaffold) provee Scaffold y SafeArea — acá se monta el
/// Scaffold mínimo y NADA más (ADR-CHW-005). Sin SingleChildScrollView: haría
/// infinito el maxHeight y la grilla necesita alto acotado.
///
/// [textScale] emula el factor de escala de texto del navegador: en Flutter web
/// sale del tamaño de fuente raíz (Chrome > Apariencia > Grande = 20/16 = 1.25).
Widget _wrap({
  Stream<List<Appointment>>? stream,
  List<Appointment> appointments = const [],
  int anchorIdx = _kColIdx,
  double textScale = 1.0,
}) {
  _lastDayTapped = null;
  return ProviderScope(
    overrides: _overrides(stream: stream, appointments: appointments),
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: AgendaWebWeekGrid(
              trainerId: _kTrainerId,
              anchorDay: _dayAt(anchorIdx),
              rangeFrom: _kWeekStart.subtract(const Duration(days: 30)),
              rangeTo: _kWeekStart.add(const Duration(days: 365)),
              onDaySelected: (d) => _lastDayTapped = d,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Rectángulo del bloque que contiene [label]: el `Container` decorado es el
/// ancestro Container más cercano al texto (los finders son por texto/tipo —
/// no hay keys en los tests de agenda).
Rect _blockRect(WidgetTester tester, String label) => tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );

/// Ancho de columna derivado del propio widget, no hardcodeado.
double _colWidth(WidgetTester tester) =>
    (tester.getSize(find.byType(AgendaWebWeekGrid)).width - kWeekGutter) / 7;

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ─── Encabezados ────────────────────────────────────────────────────────────

  group('encabezado', () {
    testWidgets('renderiza los 7 días de la semana, lunes primero',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      for (final name in [
        'Lunes', // i18n
        'Martes', // i18n
        'Miércoles', // i18n
        'Jueves', // i18n
        'Viernes', // i18n
        'Sábado', // i18n
        'Domingo', // i18n
      ]) {
        expect(find.text(name), findsOneWidget, reason: 'falta $name');
      }
    });

    testWidgets('tocar un encabezado emite onDaySelected con ese día',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jueves')); // i18n
      await tester.pumpAndSettle();

      expect(_lastDayTapped, equals(_dayAt(3)));
    });

    testWidgets(
      'las siete celdas cumplen el target de 44pt (el Row centra un Column '
      'mainAxisSize.min, que colapsaba a 39pt)',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        for (final name in [
          'Lunes', // i18n
          'Martes', // i18n
          'Miércoles', // i18n
          'Jueves', // i18n
          'Viernes', // i18n
          'Sábado', // i18n
          'Domingo', // i18n
        ]) {
          final size = tester.getSize(
            find
                .ancestor(
                  of: find.text(name),
                  matching: find.byType(GestureDetector),
                )
                .first,
          );
          expect(size.height, greaterThanOrEqualTo(44.0),
              reason: '$name: alto del target');
        }
      },
    );

    testWidgets(
      'con el texto escalado a 1.25 (Chrome "fuente grande") el encabezado '
      'crece en vez de desbordar',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap(textScale: 1.25));
        await tester.pumpAndSettle();

        // Un RenderFlex overflow es una excepción en widget tests; en release
        // el número del día se derramaría sobre el divisor y la grilla.
        expect(tester.takeException(), isNull);

        final size = tester.getSize(
          find
              .ancestor(
                of: find.text('Jueves'), // i18n
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(44.0),
            reason: 'el piso de 44pt se mantiene al escalar');
      },
    );
  });

  // ─── Ubicación de los bloques ───────────────────────────────────────────────

  group('ubicación de los bloques', () {
    testWidgets(
      'un turno de 09:30 cae 160px bajo la línea de las 07:00 y dentro de SU '
      'columna (ADR-7: sin .toLocal())',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap(appointments: [
          _appt(id: 'w1', startsAt: _at(_kColIdx, 9, 30)),
        ]));
        await tester.pumpAndSettle();

        // La etiqueta de la primera hora se dibuja 8px por encima del tope del
        // lienzo, así que la referencia es invariante al auto-scroll.
        final labelTop = tester.getTopLeft(find.text('07:00')).dy;
        final block = _blockRect(tester, '09:30');

        // (09:30 − 07:00) = 150 min → 150 × kWeekPxPerMin = 160px, +8 del
        // offset de la etiqueta. (La red de ADR-7 NO es ésta: ver el grupo
        // "ADR-7 — sin .toLocal()" al final del archivo.)
        expect(
          block.top - labelTop,
          closeTo(8 + 150 * kWeekPxPerMin, 0.5),
          reason: 'el bloque debe caer en la fila de las 09:30',
        );

        final gridLeft = tester.getTopLeft(find.byType(AgendaWebWeekGrid)).dx;
        final colWidth = _colWidth(tester);
        expect(
          block.left,
          closeTo(
            gridLeft + kWeekGutter + _kColIdx * colWidth + kWeekColInset,
            0.5,
          ),
          reason: 'el bloque debe empezar en la columna del miércoles',
        );

        // 60 min → 64px de alto.
        expect(block.height, closeTo(60 * kWeekPxPerMin, 0.5));
      },
    );

    testWidgets(
      'dos turnos que arrancan a la misma hora se reparten el ancho útil de '
      'la columna',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap(appointments: [
          _appt(id: 'w1', startsAt: _at(_kColIdx, 9, 30)),
          _appt(
            id: 'w2',
            startsAt: _at(_kColIdx, 9, 30),
            athleteId: _kAthleteB,
            athleteName: _kNameB,
          ),
        ]));
        await tester.pumpAndSettle();

        final colWidth = _colWidth(tester);
        final laneW = (colWidth - 2 * kWeekColInset) / 2;

        final a = _blockRect(tester, _kNameA);
        final b = _blockRect(tester, _kNameB);

        expect(a.width, closeTo(laneW - kWeekLaneGap, 0.5));
        expect(b.width, closeTo(laneW - kWeekLaneGap, 0.5));
        // Carriles contiguos, no apilados.
        expect((b.left - a.left).abs(), closeTo(laneW, 0.5));
        expect(a.top, closeTo(b.top, 0.5));
      },
    );
  });

  // ─── Orden de capas ─────────────────────────────────────────────────────────

  group('orden de capas', () {
    testWidgets(
      'las columnas con sus bloques se emiten DESPUÉS de las reglas horarias '
      '(si no, cada bloque queda tachado en cada hora en punto)',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap(appointments: [
          _appt(id: 'w1', startsAt: _at(_kColIdx, 9, 30)),
        ]));
        await tester.pumpAndSettle();

        // El Stack del lienzo es el primer Stack dentro del scroll view.
        final stack = tester.widget<Stack>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Stack),
              )
              .first,
        );

        // Las siete columnas viajan en un único Positioned.fill(Row); todo lo
        // que dibuja la grilla (reglas, etiquetas, tintes, divisores) va antes.
        final columnsIdx =
            stack.children.indexWhere((w) => w is Positioned && w.child is Row);
        expect(columnsIdx, greaterThan(0),
            reason:
                'la fila de columnas debe existir y no ser la primera capa');
        expect(
          stack.children.sublist(columnsIdx + 1).whereType<Positioned>(),
          isEmpty,
          reason: 'después de las columnas sólo puede ir la línea de ahora '
              '(_NowLine), nunca una regla de la grilla',
        );
      },
    );
  });

  // ─── FIX-3: carriles angostos ───────────────────────────────────────────────

  group('carriles angostos', () {
    testWidgets(
      'tres sesiones de 30 min superpuestas en 900px no desbordan '
      '(el contenido del bloque se adapta al ancho)',
      (tester) async {
        _setViewport(tester, 900);
        await tester.pumpWidget(_wrap(appointments: [
          _appt(id: 'n1', startsAt: _at(_kColIdx, 9, 5), durationMin: 30),
          _appt(
            id: 'n2',
            startsAt: _at(_kColIdx, 9, 15),
            durationMin: 30,
            athleteId: _kAthleteB,
            athleteName: _kNameB,
          ),
          _appt(
            id: 'n3',
            startsAt: _at(_kColIdx, 9, 25),
            durationMin: 30,
            athleteId: _kAthleteC,
            athleteName: _kNameC,
          ),
        ]));
        await tester.pumpAndSettle();

        // Un RenderFlex overflow es una excepción en widget tests.
        expect(tester.takeException(), isNull);

        // Los tres bloques existen y quedan en 3 carriles del ancho útil.
        final colWidth = _colWidth(tester);
        final laneW = (colWidth - 2 * kWeekColInset) / 3;
        for (final label in ['09:05', '09:15', '09:25']) {
          expect(find.text(label), findsOneWidget);
          expect(_blockRect(tester, label).width,
              closeTo(laneW - kWeekLaneGap, 0.5));
        }
      },
    );
  });

  // ─── Interacción ────────────────────────────────────────────────────────────

  group('interacción', () {
    testWidgets('tocar un bloque abre el detalle del turno', (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap(appointments: [
        _appt(id: 'w1', startsAt: _at(_kColIdx, 9, 30)),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.text(_kNameA));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets(
      'tocar una celda vacía a la altura de las 10:07 abre NUEVA SESIÓN '
      'con la hora snappeada a 10:00',
      (tester) async {
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // Tope del lienzo reconstruido desde la etiqueta de la primera hora
        // (invariante al auto-scroll).
        final canvasTop = tester.getTopLeft(find.text('07:00')).dy + 8;
        final gridLeft = tester.getTopLeft(find.byType(AgendaWebWeekGrid)).dx;
        final colWidth = _colWidth(tester);

        const startHour = 7;
        final y = canvasTop + (10 * 60 + 7 - startHour * 60) * kWeekPxPerMin;
        final x = gridLeft + kWeekGutter + (_kColIdx + 0.5) * colWidth;

        await tester.tapAt(Offset(x, y));
        await tester.pumpAndSettle();

        expect(find.byType(NewSessionDialog), findsOneWidget);

        final ctx = tester.element(find.byType(NewSessionDialog));
        final expected = const TimeOfDay(hour: 10, minute: 0).format(ctx);
        expect(find.text(expected), findsOneWidget,
            reason: 'el minuto 607 debe snappear a 10:00');
      },
    );
  });

  // ─── FIX-2: estados async ───────────────────────────────────────────────────

  group('estados async', () {
    testWidgets('el error del stream NO se confunde con una semana vacía',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap(
        stream: Stream<List<Appointment>>.error(Exception('permission-denied')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Error al cargar los turnos.'), findsOneWidget); // i18n
      // Y NO el lienzo vacío: sin las etiquetas horarias no hay grilla.
      expect(find.text('07:00'), findsNothing);
    });

    testWidgets('mientras carga muestra el spinner, no la grilla',
        (tester) async {
      _setViewport(tester, 1280);
      // Future que nunca completa → AsyncLoading sin Timer colgado.
      await tester.pumpWidget(_wrap(
        stream: Completer<List<Appointment>>().future.asStream(),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('07:00'), findsNothing);
    });

    testWidgets('una semana sin turnos igual dibuja la grilla horaria',
        (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Semilla 07:00–22:00: se etiquetan las horas 07..21 (la última regla,
      // la de las 22:00, cierra la grilla y no lleva etiqueta — mismo criterio
      // que day_timeline).
      expect(find.text('07:00'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('22:00'), findsNothing);
      expect(find.text('Lunes'), findsOneWidget); // i18n
      expect(tester.takeException(), isNull);
    });
  });

  // ─── Contrato de sección ────────────────────────────────────────────────────

  group('contrato ADR-CHW-005', () {
    testWidgets('no declara Scaffold ni SafeArea propios', (tester) async {
      _setViewport(tester, 1280);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // El único Scaffold es el del harness (en producción, el del shell).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SafeArea), findsNothing);
    });
  });

  // ─── Accesibilidad ──────────────────────────────────────────────────────────

  group('accesibilidad', () {
    testWidgets(
      'cada bloque es un botón con etiqueta autocontenida y acción de tap',
      (tester) async {
        final handle = tester.ensureSemantics();
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap(appointments: [
          _appt(id: 'w1', startsAt: _at(_kColIdx, 9, 30)),
        ]));
        await tester.pumpAndSettle();

        const label = 'Sesión con $_kNameA, 09:30 a 10:30'; // i18n
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true, label: label),
        );

        handle.dispose();
      },
    );

    testWidgets(
      'cada encabezado de día es un botón con etiqueta autocontenida '
      '(no el texto fusionado "Jueves\\n6")',
      (tester) async {
        final handle = tester.ensureSemantics();
        _setViewport(tester, 1280);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // El encabezado es el ÚNICO camino dentro de la grilla para volver a
        // la vista DÍA: sin rol de botón, VoiceOver lo lee como texto estático.
        final jueves = _dayAt(3);
        final label = 'Ver el Jueves ${jueves.day}'; // i18n
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true, label: label),
        );

        handle.dispose();
      },
    );
  });

  // ─── ADR-7: la red REAL contra el .toLocal() ────────────────────────────────

  group('ADR-7 — sin .toLocal()', () {
    // `Appointment.startsAt` es wall-clock UTC flotante: sus campos hour/minute
    // YA son hora de Argentina. Un `.toLocal()` en el camino de ubicación de
    // bloques o de cálculo del rango horario corre todo 3 horas en ART.
    //
    // Por qué un test de FUENTE y no uno de geometría: los fixtures se arman
    // con `DateTime.utc(...)`, y `DateTime.utc(x).toLocal()` es la IDENTIDAD
    // cuando el proceso corre en UTC. Los runners de GitHub Actions corren en
    // UTC (ci.yml no fija `TZ`), así que un test de píxeles pasaría en verde en
    // CI con la regresión adentro. Éste falla en cualquier huso.
    const paths = [
      'lib/features/coach_hub/presentation/sections/agenda/'
          'agenda_web_week_grid.dart',
      'lib/features/coach_hub/presentation/sections/agenda/'
          'week_grid_geometry.dart',
    ];

    for (final path in paths) {
      test('$path no llama .toLocal()', () {
        // `flutter test` corre desde la raíz del paquete.
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: 'no se encontró ${file.absolute.path}');

        // Se ignoran los comentarios: el archivo NOMBRA `.toLocal()` justamente
        // para prohibirlo, y esas menciones no deben hacer fallar el guard.
        final offenders = <int>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          if (code.contains('.toLocal()')) offenders.add(i + 1);
        }

        expect(
          offenders,
          isEmpty,
          reason: 'ADR-7: `startsAt` es wall-clock UTC flotante. Un '
              '`.toLocal()` corre los bloques 3 horas en ART. '
              'Líneas: $offenders',
        );
      });
    }
  });
}
