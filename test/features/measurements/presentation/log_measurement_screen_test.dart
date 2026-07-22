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

  testWidgets(
      '#439 edit mode: prefills the form and saves via update() preserving '
      'id/athleteId/recordedBy/recordedAt', (tester) async {
    final repo = _MockMeasurementRepository();
    when(() => repo.update(any())).thenAnswer((_) async {});

    // El caso QA del bug: 500 kg tipeados en vez de 50, hoy imposible de
    // corregir desde mobile.
    final initial = Measurement(
      id: 'm1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      weightKg: 500,
      fatPercentage: 15.5,
      notes: 'nota original',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        measurementRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogMeasurementScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    // Pre-poblado: valores exactos sin ".0" redundante, notas incluidas.
    expect(find.text('Editar medición'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('15.5'), findsOneWidget);
    expect(find.text('nota original'), findsOneWidget);

    // Corrige el typo y guarda.
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
    await tester.tap(find.text('GUARDAR CAMBIOS'));
    await tester.pump();

    final captured =
        verify(() => repo.update(captureAny())).captured.single as Measurement;
    expect(captured.id, 'm1');
    expect(captured.athleteId, 'athleteX');
    expect(captured.recordedBy, 'trainerT');
    expect(captured.recordedAt, DateTime.utc(2026, 3, 10, 14, 30),
        reason: 'editar valores no mueve el punto en la línea de tiempo');
    expect(captured.weightKg, 50);
    expect(captured.fatPercentage, 15.5);
    expect(captured.notes, 'nota original');
    verifyNever(() => repo.add(any()));
  });
}
