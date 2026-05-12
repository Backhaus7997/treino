import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';

void main() {
  testWidgets('AthleteCoachView renders COACH headline and subtitle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: AthleteCoachView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COACH'), findsOneWidget);
    expect(find.text('Personal Trainers cerca tuyo'), findsOneWidget);
  });
}
