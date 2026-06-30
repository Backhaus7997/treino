import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/workout/presentation/widgets/coach_note.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es'),
      home: Scaffold(body: w),
    );

void main() {
  group('CoachNote', () {
    testWidgets('renders the note text and the "DEL COACH" tag',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const CoachNote(text: 'Bajá 3 seg la excéntrica')),
      );
      expect(find.text('Bajá 3 seg la excéntrica'), findsOneWidget);
      expect(find.text('DEL COACH'), findsOneWidget);
    });

    testWidgets('renders nothing (no tag) for whitespace-only text',
        (tester) async {
      await tester.pumpWidget(_wrap(const CoachNote(text: '   ')));
      expect(find.text('DEL COACH'), findsNothing);
    });

    testWidgets('trims surrounding whitespace from the note text',
        (tester) async {
      await tester.pumpWidget(_wrap(const CoachNote(text: '  Pausá abajo  ')));
      expect(find.text('Pausá abajo'), findsOneWidget);
    });
  });
}
