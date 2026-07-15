import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/log_measurement_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockMeasurementRepository extends Mock
    implements MeasurementRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      Measurement(
        id: '',
        athleteId: 'x',
        recordedBy: 'x',
        recordedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  testWidgets(
      'T5: LogMeasurementScreen.selfLog attributes the measurement to the '
      'authenticated athlete (recordedBy == athleteId == uid)', (tester) async {
    final repo = _MockMeasurementRepository();
    when(() => repo.add(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as Measurement,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('athleteX'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const LogMeasurementScreen.selfLog(),
      ),
    ));
    await tester.pumpAndSettle();

    // First field is body weight. Any value enables GUARDAR.
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.pump();

    await tester.tap(find.text('GUARDAR MEDICIÓN'));
    await tester.pump();

    final captured =
        verify(() => repo.add(captureAny())).captured.single as Measurement;
    expect(captured.recordedBy, 'athleteX');
    expect(captured.athleteId, 'athleteX');
    expect(captured.weightKg, 80);
  });
}
