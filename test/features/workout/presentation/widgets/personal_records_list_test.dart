import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/widgets/personal_records_list.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PersonalRecordsListLabels _labels() => const PersonalRecordsListLabels(
      sectionTitle: 'RÉCORDS PERSONALES',
      heaviestWeightLabel: 'Peso máximo',
      oneRepMaxLabel: '1RM',
      bestSetVolumeLabel: 'Mejor serie',
      bestSessionVolumeLabel: 'Volumen',
      volumeUnit: 'kg·reps',
      weightUnit: 'kg',
      emptyText: 'Sin datos suficientes para este ejercicio.',
      localeName: 'es_AR',
    );

Widget _wrap(Widget child, {double? textScale}) => MaterialApp(
      theme: AppTheme.dark(),
      // Font scale grande inyectado por MediaQuery — misma convención que
      // post_workout_summary_screen_test.dart.
      builder: textScale == null
          ? null
          : (context, inner) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: inner!,
              ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Los 4 tipos de récord con un `bestSessionVolume` de 5 cifras + decimal — el
/// peor caso realista de ancho para el bloque valor+unidad ('12487.5 kg·reps').
List<PersonalRecord> _wideRecords() => [
      PersonalRecord(
        recordType: ProgressionRecordType.heaviestWeight,
        value: 137.5,
        achievedAt: DateTime(2025, 3, 10),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.oneRepMax,
        value: 162.5,
        achievedAt: DateTime(2025, 4, 1),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.bestSetVolume,
        value: 1237.5,
        achievedAt: DateTime(2025, 5, 20),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.bestSessionVolume,
        value: 12487.5,
        achievedAt: DateTime(2025, 6, 15),
      ),
    ];

/// Corre [body] capturando los overflows HORIZONTALES de RenderFlex.
///
/// Restaura `FlutterError.onError` antes de retornar (de ahí el `finally`):
/// el binding reporta los fallos de los `expect` por ese mismo canal, así que
/// un handler propio todavía instalado se los tragaría y el test pasaría en
/// verde igual. Los overflows verticales se descartan a propósito — a estos
/// tamaños son esperables y no son lo que este blindaje cubre.
Future<List<String>> _horizontalOverflowsDuring(
  Future<void> Function() body,
) async {
  final overflows = <String>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) {
      if (message.contains('on the right')) overflows.add(message);
      return;
    }
    originalOnError?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = originalOnError;
  }
  return overflows;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_AR');
  });

  testWidgets(
      'SCENARIO-PR-LIST-01: renders one row per record type with formatted value + date',
      (tester) async {
    final records = [
      PersonalRecord(
        recordType: ProgressionRecordType.heaviestWeight,
        value: 100,
        achievedAt: DateTime(2025, 3, 10),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.oneRepMax,
        value: 112.5,
        achievedAt: DateTime(2025, 4, 1),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.bestSetVolume,
        value: 500,
        achievedAt: DateTime(2025, 5, 20),
      ),
      PersonalRecord(
        recordType: ProgressionRecordType.bestSessionVolume,
        value: 2400,
        achievedAt: DateTime(2025, 6, 15),
      ),
    ];

    await tester.pumpWidget(_wrap(PersonalRecordsList(
      records: records,
      labels: _labels(),
    )));

    expect(find.text('RÉCORDS PERSONALES'), findsOneWidget);
    expect(find.text('Peso máximo'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('1RM'), findsOneWidget);
    expect(find.text('112.5'), findsOneWidget);
    expect(find.text('Mejor serie'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Volumen'), findsOneWidget);
    expect(find.text('2400'), findsOneWidget);
    expect(find.text('kg'), findsNWidgets(2)); // heaviestWeight + oneRepMax
    expect(find.text('kg·reps'),
        findsNWidgets(2)); // bestSetVolume + bestSessionVolume

    // Formatted date (with year, es_AR: "10 mar 2025")
    expect(find.text('10 mar 2025'), findsOneWidget);
  });

  testWidgets('SCENARIO-PR-LIST-02: empty records shows empty text',
      (tester) async {
    await tester.pumpWidget(_wrap(PersonalRecordsList(
      records: const [],
      labels: _labels(),
    )));

    expect(find.text('Sin datos suficientes para este ejercicio.'),
        findsOneWidget);
    expect(find.text('RÉCORDS PERSONALES'), findsNothing);
  });

  testWidgets('SCENARIO-PR-LIST-03: only renders rows for record types present',
      (tester) async {
    final records = [
      PersonalRecord(
        recordType: ProgressionRecordType.heaviestWeight,
        value: 80,
        achievedAt: DateTime(2025, 2, 1),
      ),
    ];

    await tester.pumpWidget(_wrap(PersonalRecordsList(
      records: records,
      labels: _labels(),
    )));

    expect(find.text('Peso máximo'), findsOneWidget);
    expect(find.text('1RM'), findsNothing);
    expect(find.text('Mejor serie'), findsNothing);
    expect(find.text('Volumen'), findsNothing);
  });

  // ── Blindaje de overflow horizontal ────────────────────────────────────────
  //
  // El bloque valor+unidad tiene ancho intrínseco y como hijo NO flexible de un
  // Row recibía ancho ILIMITADO: no podía achicarse y la fila desbordaba. Mismo
  // blindaje (flex acotado + FittedBox scaleDown) que `_SessionRecordRow` en
  // session_highlights_section.dart.

  testWidgets(
      'las filas no desbordan horizontalmente en una pantalla angosta con '
      'valores largos', (tester) async {
    tester.view.physicalSize = const Size(180, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final overflows = await _horizontalOverflowsDuring(() async {
      await tester.pumpWidget(_wrap(PersonalRecordsList(
        records: _wideRecords(),
        labels: _labels(),
      )));
      await tester.pumpAndSettle();
    });

    expect(overflows, isEmpty);
    // Las filas siguen presentes (escaladas, no descartadas).
    expect(find.text('12487.5'), findsOneWidget);
    expect(find.text('kg·reps'), findsNWidgets(2));
  });

  testWidgets(
      'las filas no desbordan con font scale de accesibilidad 3x en un ancho '
      'normal', (tester) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final overflows = await _horizontalOverflowsDuring(() async {
      await tester.pumpWidget(_wrap(
        PersonalRecordsList(records: _wideRecords(), labels: _labels()),
        textScale: 3.0,
      ));
      await tester.pumpAndSettle();
    });

    expect(overflows, isEmpty);
    expect(find.text('12487.5'), findsOneWidget);
  });

  testWidgets(
      'a ancho de teléfono normal el valor NO se escala y queda pegado al '
      'borde derecho de la card', (tester) async {
    // Este test es el contrapeso de los dos anteriores: el blindaje acota el
    // bloque de valor con un TOPE (70% del ancho), no con un reparto fijo de
    // flex. Con un reparto fijo el valor recibiría sólo su fracción y un récord
    // de volumen normal se escalaría a ~65-88% en cualquier teléfono común,
    // quedando visiblemente más chico que el de la fila de al lado.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Alto de referencia sin escalar: viewport ancho donde el tope no aplica.
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpWidget(_wrap(PersonalRecordsList(
      records: _wideRecords(),
      labels: _labels(),
    )));
    await tester.pumpAndSettle();
    final unscaledHeight = tester.getRect(find.text('12487.5')).height;

    // Mismo contenido en un ancho de teléfono normal (iPhone 14/15, Pixel).
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('12487.5')).height, unscaledHeight);

    // Pegado a la derecha: el `Expanded` del label absorbe todo el sobrante, así
    // que el bloque de valor termina contra el borde interno de la card (ancho
    // de la lista menos los 14px de padding del Container). El margen de 2px
    // cubre el side bearing natural del glifo.
    final contentRight =
        tester.getRect(find.byType(PersonalRecordsList)).right - 14;
    expect(
      tester.getRect(find.text('kg·reps').last).right,
      closeTo(contentRight, 2),
    );
  });
}
