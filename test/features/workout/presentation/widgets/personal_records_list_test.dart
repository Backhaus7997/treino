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

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

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
}
