import '../../../core/widgets/treino_icon.dart';
import 'onboarding_slide.dart';
import 'trainer_previews.dart';

/// The five slides of the trainer tour, in order.
///
/// Headlines and copy are verbatim from the trainer handoff. It is the sibling
/// of `athleteOnboardingSlides`: same shell, same slide model, different
/// content — which is the whole reason the shell takes a slide list instead of
/// knowing about roles.
///
/// Spanish hardcoded, matching the handoff and the athlete deck. When the
/// deferred i18n pass runs, both lists migrate together.
const trainerOnboardingSlides = <OnboardingSlide>[
  OnboardingSlide(
    icon: TreinoIcon.tabHome,
    title: 'TU DÍA EN UN PANTALLAZO', // i18n
    body: 'Cuántas sesiones tenés hoy, quiénes ya entrenaron y qué cobros te '
        'quedan pendientes. Todo al abrir la app.', // i18n
    preview: TrainerHomePreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabWorkout,
    title: 'ARMÁ TUS PLANTILLAS', // i18n
    body: 'Creá una plantilla de rutina una vez y asignala a los alumnos que '
        'quieras. Queda guardada en tu biblioteca para reutilizarla.', // i18n
    preview: TrainerWorkoutPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabFeed,
    title: 'SEGUÍ A TU COMUNIDAD', // i18n
    body: 'Mirá lo que publican tus alumnos y la gente de tu gym, reaccioná a '
        'sus sesiones y conseguí alumnos nuevos.', // i18n
    preview: TrainerFeedPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabCoach,
    title: 'TUS ALUMNOS, ORDENADOS', // i18n
    body: 'Gestioná cada vínculo, pausalo o cerralo cuando haga falta, y llevá '
        'tu agenda de sesiones desde la misma pestaña.', // i18n
    preview: TrainerCoachPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabProfile,
    title: 'TU PERFIL PROFESIONAL', // i18n
    body: 'Mostrate en Coach Discovery, definí tu disponibilidad y respondé '
        'las solicitudes de alumnos nuevos.', // i18n
    preview: TrainerProfilePreview(),
  ),
];
