import '../../../core/widgets/treino_icon.dart';
import '../domain/onboarding_surface.dart';
import 'custom_exercise_onboarding_art.dart';
import 'onboarding_card_content.dart';

/// The slides of the routine-editor onboarding.
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
/// The role-specific introductions differ in body copy and in the third title.
/// That is not duplication to factor out: the athlete builds a personal
/// library, the trainer builds one to assign, and the last slide is the whole
/// point of the difference.

/// The routine editor gestures are identical for athletes and trainers: they
/// depend on the mobile screen, not on the user's role. The Coach Hub editor is
/// a different screen and deliberately does not receive these slides.
const editorGestureSlides = <OnboardingCardContent>[
  OnboardingCardContent(
    icon: TreinoIcon.specialty,
    title: 'ESCRIBILO EN UNA LÍNEA', // i18n
    body: 'Tocá RÁPIDO y escribí «press de banca 4x10 55»: entra con 4 series '
        'de 10 y 55 kg. Para una pirámide, «4x10, 8, 6, 4». Para tiempo, '
        '«plancha 3x30s».', // i18n
    illustration: CustomExerciseOnboardingArt.quickEntry(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.dragHandle,
    title: 'ORDENÁ ARRASTRANDO', // i18n
    body: 'El agarre de la izquierda mueve el ejercicio. Soltalo en el centro '
        'de una superserie para meterlo adentro, o llevalo afuera para '
        'sacarlo.', // i18n
    illustration: CustomExerciseOnboardingArt.drag(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.dotsThree,
    title: 'EL RESTO ESTÁ EN EL ⋮', // i18n
    body: 'Cambiar el ejercicio, copiar los sets del anterior, subir, bajar, '
        'unir con el de arriba o el de abajo en superserie, y separarlo del '
        'grupo.', // i18n
    illustration: CustomExerciseOnboardingArt.menu(),
  ),
];

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
    // La distinción es real, no un matiz de redacción: `ExerciseVideoPlayer`
    // reproduce inline SÓLO lo subido a Storage. YouTube va como thumbnail y
    // abre un Safari View Controller / Chrome Custom Tab, porque el embed
    // inline lo rechaza el propio YouTube en WKWebView (ver el dartdoc de
    // `exercise_video_player.dart`). Prometer "inline" para los dos era
    // prometer algo que la app decidió deliberadamente no hacer.
    body: 'Subí tu MP4 / MOV y se reproduce inline mientras entrenás. O pegá '
        'un link de YouTube: se abre en un visor arriba de la app.', // i18n
    illustration: CustomExerciseOnboardingArt.video(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.dumbbell,
    title: 'USALO EN CUALQUIER RUTINA', // i18n
    body: 'Tus ejercicios quedan guardados en tu biblioteca: los agregás a '
        'cualquier día de cualquier rutina con un toque.', // i18n
    illustration: CustomExerciseOnboardingArt.library(),
  ),
  ...editorGestureSlides,
];

/// Trainer introduction — shared by mobile and the Coach Hub.
const _trainerCustomExerciseIntroduction = <OnboardingCardContent>[
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
    // Misma corrección que en el deck del alumno: inline es sólo Storage.
    body: 'Subí un MP4 / MOV y tu alumno lo ve inline en la ficha. O pegá un '
        'link de YouTube: se le abre en un visor arriba de la app.', // i18n
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

/// Trainer mobile deck — the introduction plus mobile editor gestures.
const trainerCustomExerciseSlides = <OnboardingCardContent>[
  ..._trainerCustomExerciseIntroduction,
  ...editorGestureSlides,
];

/// Coach Hub deck — introduction only.
///
/// It is intentionally separate from the trainer mobile deck: Coach Hub has no
/// RÁPIDO entry or drag handle, so teaching those gestures on web would be a
/// false promise.
const trainerWebCustomExerciseSlides = <OnboardingCardContent>[
  ..._trainerCustomExerciseIntroduction,
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
      OnboardingSurface.customExerciseTrainerMobile =>
        trainerCustomExerciseSlides,
      OnboardingSurface.customExerciseTrainerWeb =>
        trainerWebCustomExerciseSlides,
      OnboardingSurface.athleteMobile ||
      OnboardingSurface.trainerMobile ||
      OnboardingSurface.trainerWeb ||
      OnboardingSurface.templatesAthleteMobile =>
        null,
    };
