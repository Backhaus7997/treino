import '../../../core/widgets/treino_icon.dart';
import '../domain/onboarding_surface.dart';
import 'custom_exercise_onboarding_art.dart';
import 'onboarding_card_content.dart';

/// The three slides of the "Creá tus propios ejercicios" onboarding.
///
/// Copy is verbatim from the design handoff — it was written against these
/// exact screens, so paraphrasing here would quietly desync the words from the
/// picture beside them. Spanish is hardcoded with `// i18n` markers, matching
/// `athlete_onboarding_slides.dart` and `trainer_onboarding_slides.dart`; the
/// deferred i18n pass migrates all three decks together.
///
/// The chrome around the slides (SALTAR / SIGUIENTE / the step label) is NOT
/// here — it already lives in `AppL10n` and is shared with the welcome tour.
///
/// The two decks differ in body copy and in the third title only. That is not
/// duplication to factor out: the athlete builds a personal library, the
/// trainer builds one to assign, and the last slide is the whole point of the
/// difference.

/// Athlete deck — a library for their own routines.
const athleteCustomExerciseSlides = <OnboardingCardContent>[
  OnboardingCardContent(
    icon: TreinoIcon.plus,
    title: '¿FALTA UN EJERCICIO? CREÁLO VOS', // i18n
    body: 'En Agregar ejercicio → Crear nuevo cargás cualquier movimiento que '
        'no esté en el catálogo: nombre, grupo muscular, equipamiento y '
        'cues.', // i18n
    illustration: CustomExerciseOnboardingArt.form(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.video,
    title: 'SUMALE UN VIDEO', // i18n
    body: 'Pegá un link de YouTube o subí tu propio MP4 / MOV. Se reproduce '
        'inline mientras entrenás, sin salir de TREINO.', // i18n
    illustration: CustomExerciseOnboardingArt.video(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.dumbbell,
    title: 'USALO EN CUALQUIER RUTINA', // i18n
    body: 'Tus ejercicios quedan guardados en tu biblioteca: los agregás a '
        'cualquier día de cualquier rutina con un toque.', // i18n
    illustration: CustomExerciseOnboardingArt.library(),
  ),
];

/// Trainer deck — a library to assign. Used on mobile AND on the Coach Hub.
const trainerCustomExerciseSlides = <OnboardingCardContent>[
  OnboardingCardContent(
    icon: TreinoIcon.plus,
    title: '¿FALTA UN EJERCICIO? CREÁLO VOS', // i18n
    body: 'Cargá tus propios movimientos con grupo muscular, equipamiento y '
        'cues técnicos. Quedan en tu biblioteca de entrenador.', // i18n
    illustration: CustomExerciseOnboardingArt.form(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.video,
    title: 'SUMALE UN VIDEO', // i18n
    body: 'Link de YouTube o tu propio MP4 / MOV. Tu alumno lo ve inline en la '
        'ficha del ejercicio, sin salir de la app.', // i18n
    illustration: CustomExerciseOnboardingArt.video(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.dumbbell,
    title: 'ASIGNALO A TUS ALUMNOS', // i18n
    body: 'Usá tus ejercicios en cualquier rutina que armes. Cada alumno ve el '
        'video y los cues que cargaste.', // i18n
    illustration: CustomExerciseOnboardingArt.library(),
  ),
];

/// The deck for [surface], or `null` if it is not a custom-exercise surface.
///
/// Returning null rather than throwing keeps a wrong caller silent instead of
/// crashing a screen: the gates already treat "no deck" as "do not show".
List<OnboardingCardContent>? customExerciseSlidesFor(
  OnboardingSurface surface,
) =>
    switch (surface) {
      OnboardingSurface.customExerciseAthleteMobile =>
        athleteCustomExerciseSlides,
      OnboardingSurface.customExerciseTrainerMobile ||
      OnboardingSurface.customExerciseTrainerWeb =>
        trainerCustomExerciseSlides,
      OnboardingSurface.athleteMobile ||
      OnboardingSurface.trainerMobile ||
      OnboardingSurface.trainerWeb =>
        null,
    };
