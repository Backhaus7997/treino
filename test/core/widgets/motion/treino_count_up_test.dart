import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_count_up.dart';

Widget _wrap({
  required num value,
  bool disableAnimations = false,
  String Function(num value)? formatter,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: TreinoCountUp(value: value, formatter: formatter),
        ),
      ),
    ),
  );
}

void main() {
  group('TreinoCountUp', () {
    testWidgets('primer frame arranca en 0', (tester) async {
      await tester.pumpWidget(_wrap(value: 245));

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets(
        'tras la duración completa (AppMotion.slow) muestra el '
        'valor final', (tester) async {
      await tester.pumpWidget(_wrap(value: 245));

      await tester.pump(AppMotion.slow);
      expect(find.text('245'), findsOneWidget);
    });

    testWidgets('a mitad de camino muestra un valor intermedio',
        (tester) async {
      await tester.pumpWidget(_wrap(value: 100));

      await tester.pump(AppMotion.slow * 0.5);
      final shown = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(shown, greaterThan(0));
      expect(shown, lessThan(100));
    });

    testWidgets('formatter custom se aplica sobre el valor animado',
        (tester) async {
      await tester.pumpWidget(_wrap(
        value: 10,
        formatter: (v) => '${v.round()} kg',
      ));

      await tester.pump(AppMotion.slow);
      expect(find.text('10 kg'), findsOneWidget);
    });

    testWidgets('reduce-motion → muestra el valor final directo',
        (tester) async {
      await tester.pumpWidget(_wrap(value: 245, disableAnimations: true));
      // AppMotion.resolve → Duration.zero: un frame extra alcanza (mismo
      // criterio que TreinoStateSwitcher).
      await tester.pump();

      expect(find.text('245'), findsOneWidget);
    });

    testWidgets('value 0 no explota (sin división por cero en el tween)',
        (tester) async {
      await tester.pumpWidget(_wrap(value: 0));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
