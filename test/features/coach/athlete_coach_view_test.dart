import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';

void main() {
  testWidgets('AthleteCoachView mounts TrainersListScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainerDiscoveryProvider.overrideWith((_) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AthleteCoachView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TrainersListScreen), findsOneWidget);
  });
}
