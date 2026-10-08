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

/// The routine editor functions are identical for athletes and trainers: they
/// depend on the mobile screen, not on the user's role.
///
/// El Coach Hub recibe SÓLO las que existen allá — ver
/// [trainerWebCustomExerciseSlides], que comparte la de entrada rápida y las
/// dos `const` de abajo, y deja afuera el arrastre y la barra de teclado.
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
  _setTypeSlide,
  OnboardingCardContent(
    icon: TreinoIcon.copy,
    title: 'LA BARRA SOBRE EL TECLADO', // i18n
    // Es la función MÁS escondida del editor: la barra sólo existe con el
    // teclado abierto, así que quien no cargó un número nunca la vio.
    body: 'Mientras cargás un número te dice qué estás editando y suma o resta '
        'de a 2,5 kg (o 1 rep). Con «A TODAS» replicás ese peso en todos los '
        'sets del ejercicio, y si no era lo que querías, «Deshacer».', // i18n
    illustration: CustomExerciseOnboardingArt.keyboardBar(),
  ),
  _weeksSlide,
];

/// Tocar el chip de la serie. Va en las TRES superficies: el chip existe igual
/// en el teléfono y en el Coach Hub (`SetTypeChip`).
const _setTypeSlide = OnboardingCardContent(
  icon: TreinoIcon.dumbbell,
  title: 'CADA SERIE PUEDE TENER SU TIPO', // i18n
  // Nada en la pantalla dice que el número de la serie se toca. Es la razón
  // por la que esta slide existe.
  body: 'Tocá el número de la serie y elegila como Entrada en calor (W), Drop '
      '(D) o Al fallo (F). El chip cambia de glifo, así se ve de un vistazo '
      'para qué es cada serie.', // i18n
  illustration: CustomExerciseOnboardingArt.setTypes(),
);

/// Semanas y alcance. También en las tres: el Coach Hub tiene las pestañas de
/// semana, `Duplicar semana` y el mismo diálogo de alcance.
const _weeksSlide = OnboardingCardContent(
  icon: TreinoIcon.calendar,
  title: 'UN PLAN DE VARIAS SEMANAS', // i18n
  body: '«Semana» agrega otra, y «Duplicar semana» copia la anterior ejercicio '
      'por ejercicio. Cuando agregás o borrás uno, el editor te pregunta si es '
      'solo en esta semana o en todas.', // i18n
  illustration: CustomExerciseOnboardingArt.weeks(),
);

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

/// Coach Hub deck — introduction plus the WEB editor's own functions.
///
/// Sigue separado del deck del teléfono, pero ya no por lo que decía antes.
/// El comentario anterior era «Coach Hub no tiene RÁPIDO ni agarre de arrastre,
/// enseñar esos gestos en la web sería prometer algo falso». La mitad se venció:
/// la entrada rápida ES la misma en la web desde que el editor usa
/// `QuickEntryPanel` compartido, y el toggle dice `RÁPIDO` igual.
///
/// Lo que sigue siendo cierto es el arrastre: la web NO tiene
/// `ReorderableListView` ni barra de accesorio de teclado —se ordena con las
/// acciones de subir/bajar—, así que esas dos slides se quedan afuera. Y a
/// cambio tiene una que el teléfono no tiene: el panel lateral fijo (#860).
const trainerWebCustomExerciseSlides = <OnboardingCardContent>[
  ..._trainerCustomExerciseIntroduction,
  OnboardingCardContent(
    icon: TreinoIcon.specialty,
    title: 'ESCRIBILO EN UNA LÍNEA', // i18n
    body: 'Tocá RÁPIDO y escribí «press de banca 4x10 55»: entra con 4 series '
        'de 10 y 55 kg. Para una pirámide, «4x10, 8, 6, 4». Para tiempo, '
        '«plancha 3x30s».', // i18n
    illustration: CustomExerciseOnboardingArt.quickEntry(),
  ),
  OnboardingCardContent(
    icon: TreinoIcon.streak,
    title: 'EL PANEL QUEDA ABIERTO', // i18n
    // El punto del #860: el modal tapaba la rutina justo cuando hay que
    // mirarla. Sin esta slide, el botón de superserie del panel no se
    // descubre — sólo aparece con dos o más tildados.
    body: 'La lista de ejercicios vive a la derecha mientras armás: elegís, '
        'ves cómo quedó el día y seguís. Con dos o más tildados aparece «En '
        'superserie» y entran ya agrupados.', // i18n
    illustration: CustomExerciseOnboardingArt.sidePanel(),
  ),
  _setTypeSlide,
  _weeksSlide,
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
