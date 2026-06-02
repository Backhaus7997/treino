import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_list_tile.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_display.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

TrainerPublicProfile _profile({
  String uid = 'u1',
  String? displayName,
  TrainerSpecialty? specialty,
  int? rate,
  double? averageRating,
  int reviewCount = 0,
}) =>
    TrainerPublicProfile(
      uid: uid,
      displayName: displayName ?? 'Carlos Trainer',
      trainerSpecialty: specialty,
      trainerMonthlyRate: rate,
      averageRating: averageRating,
      reviewCount: reviewCount,
    );

void main() {
  group('TrainerListTile — SCENARIO-429 T26/T27', () {
    testWidgets('renders displayName', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(displayName: 'Carlos Trainer'),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      expect(find.text('Carlos Trainer'), findsOneWidget);
    });

    testWidgets('renders specialty chip when specialty set', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(specialty: TrainerSpecialty.crossfit),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      expect(find.text('crossfit'), findsOneWidget);
    });

    testWidgets('renders hourly rate when set', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(rate: 5000),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      expect(find.textContaining('5000'), findsOneWidget);
    });

    testWidgets('renders "—" when distanceKm is null', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('renders formatted distance < 10km', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(),
          distanceKm: 3.7,
          onTap: () {},
        ),
      ));
      expect(find.text('3.7 km'), findsOneWidget);
    });

    testWidgets('renders rounded distance >= 10km', (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(),
          distanceKm: 15.6,
          onTap: () {},
        ),
      ));
      expect(find.text('16 km'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(),
          distanceKm: null,
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.byType(TrainerListTile));
      expect(tapped, isTrue);
    });
  });

  group('TrainerListTile — SCENARIO-616 T44/T45 star+count row', () {
    testWidgets('SCENARIO-616: reviewCount > 0 → StarRatingDisplay visible',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(averageRating: 4.5, reviewCount: 3),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(StarRatingDisplay), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-616: reviewCount > 0 → count label visible with plural form',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(averageRating: 4.5, reviewCount: 3),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      await tester.pump();

      // i18n: Fase 6 Etapa 7
      expect(find.textContaining('3'), findsWidgets);
      // Should contain reseña copy
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('reseña') || w.data!.contains('reseñas'))),
        findsOneWidget,
      );
    });

    testWidgets('SCENARIO-616: reviewCount == 1 → singular "1 reseña"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(averageRating: 5.0, reviewCount: 1),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      await tester.pump();

      // i18n: Fase 6 Etapa 7
      expect(find.text('1 reseña'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-616: reviewCount == 0 → StarRatingDisplay hidden (ADR-RV-010)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TrainerListTile(
          profile: _profile(averageRating: null, reviewCount: 0),
          distanceKm: null,
          onTap: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(StarRatingDisplay), findsNothing);
    });
  });
}
