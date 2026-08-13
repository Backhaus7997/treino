import '../../../core/widgets/treino_icon.dart';
import 'onboarding_previews.dart';
import 'onboarding_slide.dart';

/// The five slides of the athlete tour, in order.
///
/// Copy is verbatim from the design handoff — it was written against these
/// exact screens, so paraphrasing it here would quietly desync the words from
/// the picture beside them.
///
/// Spanish is hardcoded rather than routed through `AppL10n`, matching the
/// handoff. When the deferred i18n pass runs, this list migrates with the rest.
const athleteOnboardingSlides = <OnboardingSlide>[
  OnboardingSlide(
    icon: TreinoIcon.tabHome,
    title: 'TU RESUMEN DEL DÍA', // i18n
    body: 'Acá ves qué te toca entrenar hoy, cómo venís esta semana y tu '
        'racha. Si dejaste una sesión a medias, te la ofrece para retomar.', // i18n
    preview: OnboardingHomePreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabWorkout,
    title: 'ENTRENÁ CON RUTINAS', // i18n
    body: 'Creá tus propias rutinas o entrená con el plan que te armó tu '
        'coach. Tu historial queda guardado, sesión por sesión.', // i18n
    preview: OnboardingWorkoutPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabFeed,
    title: 'COMPARTÍ TU PROGRESO', // i18n
    body: 'Mirá lo que entrenan tus amigos y tu gym, reaccioná a sus sesiones '
        'y compará tu volumen en los rankings.', // i18n
    preview: OnboardingFeedPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabCoach,
    title: 'TU COACH, SIEMPRE CERCA', // i18n
    body: 'Vinculate con un Personal Trainer, seguí el plan que te armó y '
        'escribile directo cuando lo necesites.', // i18n
    preview: OnboardingCoachPreview(),
  ),
  OnboardingSlide(
    icon: TreinoIcon.tabProfile,
    title: 'TU PERFIL, TU HISTORIA', // i18n
    body: 'Tus estadísticas, tu gym y tus datos, todo en un solo lugar. '
        'Editalos cuando quieras.', // i18n
    preview: OnboardingProfilePreview(),
  ),
];
