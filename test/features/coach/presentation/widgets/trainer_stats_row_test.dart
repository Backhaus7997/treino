import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_stats_row.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

TrainerPublicProfile _profile({
  double? averageRating,
  int reviewCount = 0,
  int? trainerExperienceYears,
  int? athleteCount,
}) =>
    TrainerPublicProfile(
      uid: 'trainer-1',
      displayName: 'Carlos Trainer',
      averageRating: averageRating,
      reviewCount: reviewCount,
      trainerExperienceYears: trainerExperienceYears,
      athleteCount: athleteCount,
    );

void main() {
  group('TrainerStatsRow — SCENARIO-617 T46/T47', () {
    testWidgets(
        'SCENARIO-617: reviewCount == 0 → RESEÑAS slot shows "—" placeholder',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(profile: _profile()),
      ));

      // The RESEÑAS label should be present
      expect(find.text('RESEÑAS'), findsOneWidget);
      // The placeholder "—" should be present for the reviews slot
      expect(find.text('—'), findsWidgets);
    });

    testWidgets(
        'SCENARIO-617: averageRating == 4.7 → shows "4.7" formatted to 1 decimal',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(averageRating: 4.7, reviewCount: 3),
        ),
      ));

      expect(find.text('4.7'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-617: reviewCount == 3, averageRating == 4.0 → shows "4.0" in RESEÑAS slot',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(averageRating: 4.0, reviewCount: 3),
        ),
      ));

      // The average rating formatted to 1 decimal should be displayed
      expect(find.text('4.0'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-617: averageRating == null, reviewCount > 0 → shows "—"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(averageRating: null, reviewCount: 2),
        ),
      ));

      expect(find.text('—'), findsWidgets);
    });
  });

  group('TrainerStatsRow — #388 AÑOS EXP y ALUMNOS reales', () {
    testWidgets(
        '#388: trainerExperienceYears y athleteCount cargados → muestra los '
        'valores reales y NINGÚN "—"', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(
            averageRating: 4.7,
            reviewCount: 3,
            trainerExperienceYears: 5,
            athleteCount: 2,
          ),
        ),
      ));

      // AÑOS EXP = 5, ALUMNOS = 2 (el caso del seed de coach.lautaro).
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('#388: athleteCount == 0 computado → muestra "0", no "—"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(athleteCount: 0),
        ),
      ));

      // 0 alumnos es dato real (CF ya computó); "—" queda solo para RESEÑAS
      // (sin reviews) y AÑOS EXP (sin cargar).
      expect(find.text('0'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets(
        '#388: sin datos cargados/computados → fallback "—" en EXP y ALUMNOS',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerStatsRow(
          profile: _profile(averageRating: 4.7, reviewCount: 3),
        ),
      ));

      // RESEÑAS resuelve 4.7; EXP y ALUMNOS null → dos placeholders.
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
    });
  });
}
