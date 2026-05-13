import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/technique_instruction_item.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('TechniqueInstructionItem', () {
    testWidgets('SCENARIO-103 (item): renders index and text', (tester) async {
      await tester.pumpWidget(_wrap(
        const TechniqueInstructionItem(index: 1, text: 'Cue 1'),
      ));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Cue 1'), findsOneWidget);
    });

    testWidgets('SCENARIO-104 (item): higher index renders without exception',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TechniqueInstructionItem(index: 3, text: 'Long cue text'),
      ));
      expect(find.text('3'), findsOneWidget);
    });
  });
}
