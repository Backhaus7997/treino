import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_volume_by_group_card.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Map<MuscleGroupDisplay, int> setsByGroup) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MonthlyVolumeByGroupCard(setsByGroup: setsByGroup),
        ),
      ),
    );

void main() {
  testWidgets('renders non-zero groups and omits zero groups', (tester) async {
    await tester.pumpWidget(_wrap(const {
      MuscleGroupDisplay.pecho: 6,
      MuscleGroupDisplay.espalda: 0,
      MuscleGroupDisplay.biceps: 3,
    }));

    expect(find.text('VOLUMEN POR GRUPO'), findsOneWidget);
    expect(find.text('PECHO'), findsOneWidget);
    expect(find.text('6 sets'), findsOneWidget);
    expect(find.text('BÍCEPS'), findsOneWidget);
    expect(find.text('3 sets'), findsOneWidget);
    expect(find.text('ESPALDA'), findsNothing);

    final bars = tester
        .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))
        .toList();
    expect(bars.map((bar) => bar.value), [1.0, 0.5]);
  });

  testWidgets('shows the monthly empty state when every group has zero sets',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      MuscleGroupDisplay.pecho: 0,
      MuscleGroupDisplay.espalda: 0,
    }));

    expect(find.text('No hay sets por grupo en este mes.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
