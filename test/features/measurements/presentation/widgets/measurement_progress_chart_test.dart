import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Measurement _m(
  DateTime recordedAt, {
  double? weightKg,
  double? fatPercentage,
  double? waistCm,
}) =>
    Measurement(
      id: 'm_${recordedAt.millisecondsSinceEpoch}',
      athleteId: 'a1',
      recordedBy: 't1',
      recordedAt: recordedAt,
      weightKg: weightKg,
      fatPercentage: fatPercentage,
      waistCm: waistCm,
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('MeasurementProgressChart', () {
    testWidgets(
        'renders the metric chip selector + line chart with ≥2 '
        'measurements for the default metric (Peso)', (tester) async {
      final measurements = [
        _m(DateTime(2026, 1, 1), weightKg: 80),
        _m(DateTime(2026, 2, 1), weightKg: 78),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESO'), findsOneWidget);
      expect(find.text('Peso'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('only offers metrics with ≥2 non-null data points as chips',
        (tester) async {
      final measurements = [
        // weightKg has 2 points, fatPercentage only 1 → Peso chip only.
        _m(DateTime(2026, 1, 1), weightKg: 80, fatPercentage: 18),
        _m(DateTime(2026, 2, 1), weightKg: 78),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Peso'), findsOneWidget);
      expect(find.text('% Graso'), findsNothing);
    });

    testWidgets('tapping a chip switches the plotted metric + header value',
        (tester) async {
      final measurements = [
        _m(DateTime(2026, 1, 1), weightKg: 80, waistCm: 90),
        _m(DateTime(2026, 2, 1), weightKg: 78, waistCm: 88),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      // Default metric is the first available in preferred order (Peso).
      expect(find.text('78'), findsOneWidget);

      await tester.tap(find.text('Cintura'));
      await tester.pumpAndSettle();

      expect(find.text('88'), findsOneWidget);
      expect(find.text('78'), findsNothing);
    });

    testWidgets(
        'does NOT render the line chart when the selected metric has fewer '
        'than 2 data points (e.g. a single measurement overall)',
        (tester) async {
      final measurements = [_m(DateTime(2026, 1, 1), weightKg: 80)];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESO'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets(
        'switching to a widget with different measurements (didUpdateWidget) '
        'resets to a still-valid selection or falls back to the first metric',
        (tester) async {
      final first = [
        _m(DateTime(2026, 1, 1), weightKg: 80, waistCm: 90),
        _m(DateTime(2026, 2, 1), weightKg: 78, waistCm: 88),
      ];
      // New measurement set no longer has waist data at all.
      final second = [
        _m(DateTime(2026, 3, 1), weightKg: 76),
        _m(DateTime(2026, 4, 1), weightKg: 75),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: first),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cintura'));
      await tester.pumpAndSettle();
      expect(find.text('88'), findsOneWidget);

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: second),
      ));
      await tester.pumpAndSettle();

      // 'Cintura' chip is gone (no waist data in the new set) — selection
      // must have reset to the first available metric (Peso), not crash.
      expect(find.text('Cintura'), findsNothing);
      expect(find.text('Peso'), findsOneWidget);
      expect(find.text('75'), findsOneWidget);
    });

    // ── #554: dedupe de etiquetas del eje X ───────────────────────────────────
    //
    // Mismo defecto que #383 arregló en el chart de progresión (PR #463): sin
    // `interval` fijo, fl_chart samplea Xs fraccionarias y value.round() mapea
    // samples vecinos al mismo índice → '21 abr | 21 abr | 19 may | 19 may'.

    testWidgets(
        '#554: métrica con huecos (5 puntos sobre 7 mediciones) renderiza '
        'cada etiqueta visible exactamente una vez', (tester) async {
      // Repro del issue: 7 mediciones quincenales, la serie Peso sólo tiene
      // valor en 5 (índices 0, 2, 3, 5, 6). UTC-flagged noon (frame ART).
      final measurements = [
        _m(DateTime.utc(2026, 4, 7, 12), weightKg: 80),
        _m(DateTime.utc(2026, 4, 21, 12), fatPercentage: 18),
        _m(DateTime.utc(2026, 5, 5, 12), weightKg: 79),
        _m(DateTime.utc(2026, 5, 19, 12), weightKg: 78.5),
        _m(DateTime.utc(2026, 6, 2, 12), fatPercentage: 17),
        _m(DateTime.utc(2026, 6, 16, 12), weightKg: 78),
        _m(DateTime.utc(2026, 6, 30, 12), weightKg: 77.5),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      // Con puntos en los índices [0, 2, 3, 5, 6], _labelIndices elige
      // {primero, último, ~2 intermedios} → {0, 2, 5, 6}.
      for (final label in ['7 abr', '5 may', '16 jun', '30 jun']) {
        expect(find.text(label), findsOneWidget,
            reason: 'la etiqueta "$label" debe aparecer exactamente una vez');
      }
      // Fuera del subset (o sin punto de Peso) → sin etiqueta.
      for (final label in ['21 abr', '19 may', '2 jun']) {
        expect(find.text(label), findsNothing,
            reason: '"$label" no integra el subset de etiquetas');
      }
    });

    testWidgets('#554: ≤4 puntos etiqueta cada medición exactamente una vez',
        (tester) async {
      final measurements = [
        _m(DateTime.utc(2026, 4, 7, 12), weightKg: 80),
        _m(DateTime.utc(2026, 4, 21, 12), weightKg: 79),
        _m(DateTime.utc(2026, 5, 5, 12), weightKg: 78),
      ];

      await tester.pumpWidget(_wrap(
        MeasurementProgressChart(measurements: measurements),
      ));
      await tester.pumpAndSettle();

      for (final label in ['7 abr', '21 abr', '5 may']) {
        expect(find.text(label), findsOneWidget,
            reason: 'la etiqueta "$label" debe aparecer exactamente una vez');
      }
    });
  });
}
