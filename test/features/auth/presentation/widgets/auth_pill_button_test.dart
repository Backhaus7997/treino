import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('AuthPillButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(_wrap(
        AuthPillButton(label: 'ENTRAR', onPressed: () {}),
      ));
      await tester.pump();
      expect(find.text('ENTRAR'), findsOneWidget);
    });

    testWidgets('tapping fires onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AuthPillButton(label: 'ENTRAR', onPressed: () => tapped = true),
      ));
      await tester.pump();
      await tester.tap(find.byType(AuthPillButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
        'loading state shows CircularProgressIndicator and disables tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        AuthPillButton(
          label: 'ENTRAR',
          onPressed: () => tapped = true,
          isLoading: true,
        ),
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ENTRAR'), findsNothing);
      await tester.tap(find.byType(AuthPillButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('disabled state (onPressed null) — button cannot be tapped',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        const AuthPillButton(label: 'ENTRAR', onPressed: null),
      ));
      await tester.pump();
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
      expect(tapped, isFalse);
    });
  });
}
