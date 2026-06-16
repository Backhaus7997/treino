import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/presentation/widgets/auth_input.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('AuthInput inputFormatters (step 4 height fix)', () {
    testWidgets('digitsOnly formatter strips decimals and separators',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'ALTURA (CM)',
          leadingIcon: TreinoIcon.ruler,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ));
      await tester.pump();

      // User types a decimal height like '168.5' — the formatter must drop the
      // '.' so the controller only ever holds an integer-parsable value, which
      // prevents int.tryParse from silently returning null in _syncHeight.
      await tester.enterText(find.byType(TextFormField), '168.5');
      await tester.pump();

      expect(ctrl.text, '1685');
      expect(int.tryParse(ctrl.text), isNotNull);
    });

    testWidgets('without formatter the field would keep the decimal',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(_wrap(
        AuthInput(
          controller: ctrl,
          label: 'ALTURA (CM)',
          leadingIcon: TreinoIcon.ruler,
          keyboardType: TextInputType.number,
        ),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '168.5');
      await tester.pump();

      // Documents the original buggy condition: a decimal survives and
      // int.tryParse would return null.
      expect(ctrl.text, '168.5');
      expect(int.tryParse(ctrl.text), isNull);
    });
  });
}
