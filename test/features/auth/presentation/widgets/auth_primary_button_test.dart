import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/widgets/auth_primary_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AuthPrimaryButton', () {
    testWidgets('isLoading:true shows CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          AuthPrimaryButton(
            label: 'Iniciar sesión',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('isLoading:true disables button (onPressed is null)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          AuthPrimaryButton(
            label: 'Iniciar sesión',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      );
      // The ElevatedButton should have onPressed null when loading
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('isLoading:false + callback → tap calls callback',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          AuthPrimaryButton(
            label: 'Iniciar sesión',
            onPressed: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      expect(tapped, isTrue);
    });

    testWidgets('onPressed:null + isLoading:false → button disabled',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AuthPrimaryButton(label: 'Iniciar sesión', onPressed: null),
        ),
      );
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('label text is shown when not loading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AuthPrimaryButton(label: 'Crear cuenta', onPressed: () {}),
        ),
      );
      expect(find.text('Crear cuenta'), findsOneWidget);
    });
  });
}
