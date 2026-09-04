import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_slides.dart';

void main() {
  // Las funciones del editor del TELÉFONO, en orden.
  const funcionesMobile = <String>[
    'ESCRIBILO EN UNA LÍNEA',
    'ORDENÁ ARRASTRANDO',
    'EL RESTO ESTÁ EN EL ⋮',
    'CADA SERIE PUEDE TENER SU TIPO',
    'LA BARRA SOBRE EL TECLADO',
    'UN PLAN DE VARIAS SEMANAS',
  ];

  // Las dos que la web NO tiene. Es la aserción que más importa del archivo:
  // el editor web no tiene `ReorderableListView` ni barra de accesorio de
  // teclado, así que enseñar esos gestos allá sería prometer algo que no
  // existe.
  const soloMobile = <String>[
    'ORDENÁ ARRASTRANDO',
    'LA BARRA SOBRE EL TECLADO',
  ];

  List<String> titulos(OnboardingSurface s) =>
      customExerciseSlidesFor(s)!.map((slide) => slide.title).toList();

  test('el deck del alumno cierra con las 6 funciones del editor', () {
    final deck = customExerciseSlidesFor(
      OnboardingSurface.customExerciseAthleteMobile,
    )!;

    expect(deck, hasLength(9));
    expect(deck.skip(3).map((slide) => slide.title), funcionesMobile);
  });

  test('el deck del entrenador en el teléfono, igual', () {
    final deck = customExerciseSlidesFor(
      OnboardingSurface.customExerciseTrainerMobile,
    )!;

    expect(deck, hasLength(9));
    expect(deck.skip(3).map((slide) => slide.title), funcionesMobile);
  });

  test('la web enseña la entrada rápida: desde el editor compartido, la tiene',
      () {
    // El comentario que había acá antes decía que la web no tenía RÁPIDO. Se
    // venció cuando el editor web pasó a usar `QuickEntryPanel` compartido.
    expect(titulos(OnboardingSurface.customExerciseTrainerWeb),
        contains('ESCRIBILO EN UNA LÍNEA'));
  });

  test('la web NO promete el arrastre ni la barra de teclado', () {
    final web = titulos(OnboardingSurface.customExerciseTrainerWeb);

    for (final titulo in soloMobile) {
      expect(web, isNot(contains(titulo)),
          reason: 'la web no tiene esa función: enseñarla es mentirle al PF');
    }
  });

  test('la web suma la suya: el panel lateral', () {
    final web = titulos(OnboardingSurface.customExerciseTrainerWeb);

    expect(web, hasLength(7));
    expect(web, contains('EL PANEL QUEDA ABIERTO'));
    // Y el teléfono no la recibe, porque allá no hay panel.
    expect(titulos(OnboardingSurface.customExerciseTrainerMobile),
        isNot(contains('EL PANEL QUEDA ABIERTO')));
  });

  test('lo que existe en las dos superficies está en las dos', () {
    // El chip de la serie (`SetTypeChip`) y las semanas existen igual en el
    // teléfono y en el Coach Hub, así que ningún deck se las puede saltear.
    for (final compartida in [
      'CADA SERIE PUEDE TENER SU TIPO',
      'UN PLAN DE VARIAS SEMANAS',
    ]) {
      for (final s in [
        OnboardingSurface.customExerciseAthleteMobile,
        OnboardingSurface.customExerciseTrainerMobile,
        OnboardingSurface.customExerciseTrainerWeb,
      ]) {
        expect(titulos(s), contains(compartida), reason: '$compartida en $s');
      }
    }
  });

  test('ninguna slide del editor se queda sin ilustración', () {
    for (final s in [
      OnboardingSurface.customExerciseAthleteMobile,
      OnboardingSurface.customExerciseTrainerMobile,
      OnboardingSurface.customExerciseTrainerWeb,
    ]) {
      for (final slide in customExerciseSlidesFor(s)!) {
        expect(slide.illustration, isNotNull,
            reason: '${slide.title} en $s se quedó sin dibujo');
      }
    }
  });
}
