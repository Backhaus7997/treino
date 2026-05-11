import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/experience_level.dart';
import '../domain/gender.dart';
import '../domain/profile_setup_draft.dart';

/// Estado in-memory del flow: el draft del usuario + el step actual (0..3).
class ProfileSetupState {
  const ProfileSetupState({
    required this.draft,
    required this.currentStep,
  });

  final ProfileSetupDraft draft;
  final int currentStep;

  ProfileSetupState copyWith({
    ProfileSetupDraft? draft,
    int? currentStep,
  }) =>
      ProfileSetupState(
        draft: draft ?? this.draft,
        currentStep: currentStep ?? this.currentStep,
      );

  static const total = 4;

  bool get canGoNext => switch (currentStep) {
        0 => draft.isStep1Valid,
        1 => draft.isStep2Valid,
        2 => draft.isStep3Valid,
        3 => draft.isStep4Valid,
        _ => false,
      };

  bool get isLastStep => currentStep == total - 1;
}

class ProfileSetupNotifier extends Notifier<ProfileSetupState> {
  @override
  ProfileSetupState build() => const ProfileSetupState(
        draft: ProfileSetupDraft(),
        currentStep: 0,
      );

  // ---------- Step navigation ----------

  void goNext() {
    if (!state.canGoNext || state.isLastStep) return;
    state = state.copyWith(currentStep: state.currentStep + 1);
  }

  void goBack() {
    if (state.currentStep == 0) return;
    state = state.copyWith(currentStep: state.currentStep - 1);
  }

  // ---------- Field updates ----------

  void updateUsername(String value) =>
      state = state.copyWith(draft: state.draft.copyWith(username: value));

  void updateAvatarLocalPath(String? value) => state = state.copyWith(
        draft: state.draft.copyWith(avatarLocalPath: value),
      );

  void updateAvatarRemoteUrl(String? value) => state = state.copyWith(
        draft: state.draft.copyWith(avatarRemoteUrl: value),
      );

  void updateGymId(String? value) =>
      state = state.copyWith(draft: state.draft.copyWith(gymId: value));

  void updateExperience(ExperienceLevel value) => state = state.copyWith(
        draft: state.draft.copyWith(experience: value),
      );

  void updateGender(Gender value) =>
      state = state.copyWith(draft: state.draft.copyWith(gender: value));

  void updateWeightKg(double? value) =>
      state = state.copyWith(draft: state.draft.copyWith(weightKg: value));

  void updateHeightCm(double? value) =>
      state = state.copyWith(draft: state.draft.copyWith(heightCm: value));

  // ---------- Submit ----------

  /// TODO(etapa3): cuando UserRepository exista, mapear el draft a UserProfile
  /// y persistirlo en Firestore en `users/{uid}`. También uploadear avatar a
  /// Firebase Storage primero y guardar la URL en avatarRemoteUrl.
  ///
  /// Por ahora es no-op: el caller decide qué hacer (típicamente navegar a
  /// /home).
  Future<void> submit() async {
    // No-op stub until Etapa 3 lands.
  }
}
