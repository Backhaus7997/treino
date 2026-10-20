import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/trainer_inquiry_card.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
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
      expect(find.textContaining('treino@gettreino.com'), findsOneWidget);
    });

    // Codex en #1599: con un GestureDetector la tarjeta no entraba en el foco
    // ni se activaba con teclado (web, teclado físico, Switch Control).
    testWidgets('se alcanza con Tab y se activa con Enter', (tester) async {
      var tocada = 0;
      await tester.pumpWidget(_wrap(TrainerInquiryCard(onTap: () => tocada++)));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tocada, 1);
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
