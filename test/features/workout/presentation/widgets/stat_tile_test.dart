import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('StatTile', () {
    testWidgets('SCENARIO-095: label and value are both rendered',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'EJERCICIOS', value: '6'),
      ));
      expect(find.text('EJERCICIOS'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('SCENARIO-096: value null renders dash without exception',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'DURACIÓN', value: null),
      ));
      expect(find.text('—'), findsOneWidget);
    });
  });
}
