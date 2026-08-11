import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/domain/user_role.dart';
import '../domain/onboarding_module.dart';
import 'onboarding_card_content.dart';
import 'onboarding_illustration.dart';

/// Copy for each (module, role) pair on mobile.
///
/// Inclusion rule: "if the user never discovers this, does the product fail
/// them?" — not "is this nice to know?". A card that narrates what is already
/// on screen is noise; the ones worth writing name a rule the UI does not show.
///
/// The two that carry the most weight:
///  - Athlete COACH: workouts are shared automatically once the link is active
///    (a Cloud Function writes `session_shares`), while personal data and
///    measurements need the Perfil › PRIVACIDAD toggle (`profile_shares`).
///    Nothing on screen says which is which.
///  - Trainer COACH: the link request originates on the ATHLETE's side. A coach
///    who does not know that waits forever with an empty roster — failure
///    mode #1 for a brand-new trainer.
///
/// Returns `null` for web modules: the Coach Hub owns its own copy, hardcoded in
/// Spanish per that module's i18n constraint.
OnboardingCardContent? mobileCardContent(
  OnboardingModule module,
  UserRole role,
  AppL10n l10n,
) {
  final isAthlete = role == UserRole.athlete;

  switch (module) {
    case OnboardingModule.home:
      return isAthlete
          ? OnboardingCardContent(
              icon: TreinoIcon.tabHome,
              illustration: const OnboardingIllustration.athleteHome(),
              title: l10n.onboardingCardAthleteHomeTitle,
              body: l10n.onboardingCardAthleteHomeBody,
            )
          : OnboardingCardContent(
              icon: TreinoIcon.tabHome,
              illustration: const OnboardingIllustration.trainerHome(),
              title: l10n.onboardingCardTrainerHomeTitle,
              body: l10n.onboardingCardTrainerHomeBody,
            );

    case OnboardingModule.workout:
      return isAthlete
          ? OnboardingCardContent(
              icon: TreinoIcon.tabWorkout,
              illustration: const OnboardingIllustration.athleteWorkout(),
              title: l10n.onboardingCardAthleteWorkoutTitle,
              body: l10n.onboardingCardAthleteWorkoutBody,
              bullets: [
                l10n.onboardingCardAthleteWorkoutBullet1,
                l10n.onboardingCardAthleteWorkoutBullet2,
                l10n.onboardingCardAthleteWorkoutBullet3,
              ],
            )
          : OnboardingCardContent(
              icon: TreinoIcon.tabWorkout,
              illustration: const OnboardingIllustration.trainerWorkout(),
              title: l10n.onboardingCardTrainerWorkoutTitle,
              body: l10n.onboardingCardTrainerWorkoutBody,
            );

    case OnboardingModule.feed:
      // Rankings is a LABELLED tab beside FEED — and only for athletes. The
      // trainer sees the feed with no tab bar, so their copy must not mention it
      // and their illustration must not draw the pill.
      return isAthlete
          ? OnboardingCardContent(
              icon: TreinoIcon.tabFeed,
              illustration: const OnboardingIllustration.athleteFeed(),
              title: l10n.onboardingCardAthleteFeedTitle,
              body: l10n.onboardingCardAthleteFeedBody,
              bullets: [
                l10n.onboardingCardAthleteFeedBullet1,
                l10n.onboardingCardAthleteFeedBullet2,
              ],
            )
          : OnboardingCardContent(
              icon: TreinoIcon.tabFeed,
              illustration: const OnboardingIllustration.trainerFeed(),
              title: l10n.onboardingCardTrainerFeedTitle,
              body: l10n.onboardingCardTrainerFeedBody,
            );

    case OnboardingModule.coach:
      return isAthlete
          ? OnboardingCardContent(
              icon: TreinoIcon.tabCoach,
              illustration: const OnboardingIllustration.athleteCoach(),
              title: l10n.onboardingCardAthleteCoachTitle,
              body: l10n.onboardingCardAthleteCoachBody,
              bullets: [
                l10n.onboardingCardAthleteCoachBullet1,
                l10n.onboardingCardAthleteCoachBullet2,
              ],
            )
          : OnboardingCardContent(
              icon: TreinoIcon.tabCoach,
              illustration: const OnboardingIllustration.trainerCoach(),
              title: l10n.onboardingCardTrainerCoachTitle,
              body: l10n.onboardingCardTrainerCoachBody,
              bullets: [
                l10n.onboardingCardTrainerCoachBullet1,
                l10n.onboardingCardTrainerCoachBullet2,
                l10n.onboardingCardTrainerCoachBullet3,
              ],
            );

    case OnboardingModule.profile:
      return isAthlete
          ? OnboardingCardContent(
              icon: TreinoIcon.tabProfile,
              illustration: const OnboardingIllustration.athleteProfile(),
              title: l10n.onboardingCardAthleteProfileTitle,
              body: l10n.onboardingCardAthleteProfileBody,
            )
          : OnboardingCardContent(
              icon: TreinoIcon.tabProfile,
              illustration: const OnboardingIllustration.trainerProfile(),
              title: l10n.onboardingCardTrainerProfileTitle,
              body: l10n.onboardingCardTrainerProfileBody,
              bullets: [
                l10n.onboardingCardTrainerProfileBullet1,
                l10n.onboardingCardTrainerProfileBullet2,
              ],
            );

    case OnboardingModule.webDashboard:
    case OnboardingModule.webAlumnos:
    case OnboardingModule.webAgenda:
    case OnboardingModule.webChat:
    case OnboardingModule.webBiblioteca:
    case OnboardingModule.webRutinas:
    case OnboardingModule.webPagos:
    case OnboardingModule.webAjustes:
      return null;
  }
}
