import 'user_profile.dart';

/// Extension on [UserProfile] that derives whether a trainer's public profile
/// is sufficiently complete to be discoverable via TrainersListScreen.
///
/// The check is pure boolean algebra over existing Firestore-backed fields —
/// no new model field, no Freezed regen, no migration required.
///
/// Formula (ADR-TPO-004):
///   trainerBio != null
///   && trainerSpecialty != null
///   && trainerMonthlyRate != null
///   && (trainerLocations.isNotEmpty || trainerOffersOnline == true)
///
/// REQ-TPO-DATA-004.
extension UserProfileTrainerCompleteness on UserProfile {
  bool get trainerProfileComplete {
    return trainerBio != null &&
        trainerSpecialty != null &&
        trainerMonthlyRate != null &&
        (trainerLocations.isNotEmpty || trainerOffersOnline);
  }
}
