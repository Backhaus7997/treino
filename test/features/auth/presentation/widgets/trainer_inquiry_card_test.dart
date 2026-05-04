import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/trainer_inquiry_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('TrainerInquiryCard', () {
    testWidgets('renders shield icon, title and subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const TrainerInquiryCard()));
      await tester.pump();

      expect(find.text('¿Sos entrenador?'), findsOneWidget);
      expect(find.text('Pedí tu alta al equipo TREINO'), findsOneWidget);
    });

    testWidgets('tapping opens AlertDialog with email', (tester) async {
      await tester.pumpWidget(_wrap(const TrainerInquiryCard()));
      await tester.pump();

      await tester.tap(find.byType(TrainerInquiryCard));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('equipo@treino.app'), findsOneWidget);
    });

    testWidgets('AlertDialog has Cerrar button that closes it', (tester) async {
      await tester.pumpWidget(_wrap(const TrainerInquiryCard()));
      await tester.pump();

      await tester.tap(find.byType(TrainerInquiryCard));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
