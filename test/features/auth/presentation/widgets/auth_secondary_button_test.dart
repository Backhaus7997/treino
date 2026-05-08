import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('AuthSecondaryButton', () {
    testWidgets('renders icon and label', (tester) async {
      await tester.pumpWidget(_wrap(
        AuthSecondaryButton(
          icon: TreinoIcon.googleLogo,
          label: 'GOOGLE',
          onPressed: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('GOOGLE'), findsOneWidget);
      expect(find.byIcon(TreinoIcon.googleLogo), findsOneWidget);
    });

    testWidgets('tapping enabled button fires onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AuthSecondaryButton(
          icon: TreinoIcon.googleLogo,
          label: 'GOOGLE',
          onPressed: () => tapped = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byType(AuthSecondaryButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const AuthSecondaryButton(
          icon: TreinoIcon.googleLogo,
          label: 'GOOGLE',
          onPressed: null,
        ),
      ));
      await tester.pump();
      // OutlinedButton should have null onPressed
      final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('disabled button is wrapped in Tooltip with Próximamente',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const AuthSecondaryButton(
          icon: TreinoIcon.appleLogo,
          label: 'APPLE',
          onPressed: null,
        ),
      ));
      await tester.pump();
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Próximamente');
    });
  });
}
