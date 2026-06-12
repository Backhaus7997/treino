import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile_setup/presentation/widgets/profile_setup_header.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    );

void main() {
  group('ProfileSetupHeader', () {
    testWidgets('title is clamped to 2 lines with ellipsis', (tester) async {
      await tester.pumpWidget(_wrap(
        const ProfileSetupHeader(
          currentStep: 0,
          title: '¿CÓMO TE LLAMÁS?',
        ),
      ));
      await tester.pump();

      final titleText = tester.widget<Text>(find.text('¿CÓMO TE LLAMÁS?'));
      expect(titleText.maxLines, 2);
      expect(titleText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('renders without overflow at large text scale', (tester) async {
      await tester.pumpWidget(_wrap(
        const ProfileSetupHeader(
          currentStep: 3,
          title: 'PESO Y ALTURA',
        ),
        textScale: 2.0,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
