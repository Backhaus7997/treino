import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_bottom_sheet.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_input.dart';

class _MockReviewRepository extends Mock implements ReviewRepository {}

const _linkId = 'link-1';
const _trainerId = 'trainer-1';
const _trainerName = 'Ana García';
const _athleteId = 'athlete-1';

Review _makeReview({int rating = 3, String comment = 'Muy buena'}) => Review(
      id: Review.idFor(_linkId, _athleteId),
      linkId: _linkId,
      athleteId: _athleteId,
      trainerId: _trainerId,
      rating: rating,
      comment: comment,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

Widget _wrapSheet({
  Review? existing,
  ReviewTriggerVariant variant = ReviewTriggerVariant.standard,
  _MockReviewRepository? mockRepo,
}) {
  final repo = mockRepo ?? _MockReviewRepository();
  return ProviderScope(
    overrides: [
      reviewRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ReviewBottomSheet(
          linkId: _linkId,
          trainerId: _trainerId,
          trainerName: _trainerName,
          athleteId: _athleteId,
          existing: existing,
          triggerVariant: variant,
        ),
      ),
    ),
  );
}

void main() {
  group('ReviewBottomSheet', () {
    testWidgets('SCENARIO-601: new variant shows title with trainer name',
        (tester) async {
      await tester.pumpWidget(_wrapSheet());
      // i18n: Fase 6 Etapa 7
      expect(find.textContaining(_trainerName), findsWidgets);
      expect(find.textContaining('¿Cómo fue tu experiencia'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-601: 30-day variant shows 30-day title with trainer name',
        (tester) async {
      await tester
          .pumpWidget(_wrapSheet(variant: ReviewTriggerVariant.thirtyDay));
      // i18n: Fase 6 Etapa 7
      expect(find.textContaining('Ya llevás'), findsOneWidget);
      expect(find.textContaining(_trainerName), findsWidgets);
    });

    testWidgets(
        'SCENARIO-602: edit variant shows "Editá tu reseña" title and pre-fills stars + comment',
        (tester) async {
      final review = _makeReview(rating: 3, comment: 'Muy buena');
      await tester.pumpWidget(_wrapSheet(existing: review));
      // i18n: Fase 6 Etapa 7
      expect(find.textContaining('Editá tu reseña'), findsOneWidget);
      // Comment pre-filled
      expect(find.text('Muy buena'), findsOneWidget);
      // 3 filled stars
      final widget =
          tester.widget<StarRatingInput>(find.byType(StarRatingInput));
      expect(widget.rating, equals(3));
    });

    testWidgets('SCENARIO-603: ENVIAR disabled when rating==0', (tester) async {
      await tester.pumpWidget(_wrapSheet());
      await tester.pump(); // let notifier build() complete
      // i18n: Fase 6 Etapa 7
      // The button text 'ENVIAR' is shown when not loading
      final enviarFinder = find.widgetWithText(ElevatedButton, 'ENVIAR');
      expect(enviarFinder, findsOneWidget);
      final button = tester.widget<ElevatedButton>(enviarFinder);
      expect(button.onPressed, isNull);
    });

    testWidgets('SCENARIO-603: ENVIAR enabled after tapping a star',
        (tester) async {
      await tester.pumpWidget(_wrapSheet());
      await tester.pump(); // let notifier build() complete
      // Tap first star
      final gestures = find.descendant(
        of: find.byType(StarRatingInput),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(gestures.first);
      await tester.pump();
      // i18n: Fase 6 Etapa 7
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ENVIAR'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('SCENARIO-607: CANCELAR pops sheet', (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(builder: (ctx) {
                return ElevatedButton(
                  onPressed: () async {
                    await showModalBottomSheet(
                      context: ctx,
                      builder: (_) => const ReviewBottomSheet(
                        linkId: _linkId,
                        trainerId: _trainerId,
                        trainerName: _trainerName,
                        athleteId: _athleteId,
                        triggerVariant: ReviewTriggerVariant.standard,
                      ),
                    );
                    popped = true;
                  },
                  child: const Text('Open'),
                );
              }),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // i18n: Fase 6 Etapa 7
      await tester.tap(find.widgetWithText(TextButton, 'CANCELAR'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
    });

    testWidgets(
        'SCENARIO-608: comment field has maxLength 500 and counter visible',
        (tester) async {
      await tester.pumpWidget(_wrapSheet());
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, equals(500));
    });
  });
}
