import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_slides.dart';

void main() {
  const gestureTitles = <String>[
    'ESCRIBILO EN UNA LÍNEA',
    'ORDENÁ ARRASTRANDO',
    'EL RESTO ESTÁ EN EL ⋮',
  ];

  test('athlete mobile ends with the three editor gesture slides', () {
    final deck = customExerciseSlidesFor(
      OnboardingSurface.customExerciseAthleteMobile,
    )!;

    expect(deck, hasLength(6));
    expect(deck.skip(3).map((slide) => slide.title), gestureTitles);
  });

  test('trainer mobile ends with the three editor gesture slides', () {
    final deck = customExerciseSlidesFor(
      OnboardingSurface.customExerciseTrainerMobile,
    )!;

    expect(deck, hasLength(6));
    expect(deck.skip(3).map((slide) => slide.title), gestureTitles);
  });

  test('trainer web keeps only its three original slides', () {
    final deck = customExerciseSlidesFor(
      OnboardingSurface.customExerciseTrainerWeb,
    )!;

    expect(deck, hasLength(3));
    expect(
      deck.map((slide) => slide.title),
      isNot(containsAll(gestureTitles)),
    );
    expect(
      deck.any((slide) => gestureTitles.contains(slide.title)),
      isFalse,
    );
  });
}
