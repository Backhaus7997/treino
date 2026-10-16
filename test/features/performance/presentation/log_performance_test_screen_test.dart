import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/data/performance_test_repository.dart';
import 'package:treino/features/performance/presentation/log_performance_test_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockPerformanceTestRepository extends Mock
    implements PerformanceTestRepository {}

void main() {
  testWidgets(
      '#1485: un CMJ de 999 cm muestra el rango, deshabilita GUARDAR, y al '
      'corregir el error se va', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider
            .overrideWithValue(_MockPerformanceTestRepository()),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const LogPerformanceTestScreen(athleteId: 'athleteX'),
      ),
    ));
    await tester.pumpAndSettle();

    ButtonStyleButton guardar() => tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('GUARDAR EVALUACIÓN'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );

    // Primer campo: CMJ.
    final cmj = find.byType(TextField).first;
    await tester.enterText(cmj, '999');
    await tester.pump();

    expect(find.text('Entre 0 y 150 cm'), findsOneWidget);
    expect(guardar().onPressed, isNull);

    await tester.enterText(cmj, '42,5');
    await tester.pump();

    expect(find.text('Entre 0 y 150 cm'), findsNothing);
    expect(guardar().onPressed, isNotNull);
  });
}
