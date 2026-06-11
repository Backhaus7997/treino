import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart' show firebaseAuthProvider;
import '../../profile/application/user_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';
import '../domain/gym.dart';
import '../domain/profile_setup_draft.dart';
import 'profile_setup_providers.dart' show avatarUploadServiceProvider;

/// Estado in-memory del flow: el draft del usuario + el step actual (0..3) +
/// flags de submit (loading / error).
class ProfileSetupState {
  const ProfileSetupState({
    required this.draft,
    required this.currentStep,
    this.isSubmitting = false,
    this.submitError,
  });

  final ProfileSetupDraft draft;
  final int currentStep;
  final bool isSubmitting;
  final Object? submitError;

  ProfileSetupState copyWith({
    ProfileSetupDraft? draft,
    int? currentStep,
    bool? isSubmitting,
    Object? submitError,
    bool clearSubmitError = false,
  }) =>
      ProfileSetupState(
        draft: draft ?? this.draft,
        currentStep: currentStep ?? this.currentStep,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        submitError:
            clearSubmitError ? null : (submitError ?? this.submitError),
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

  void updateGymId(String? value) =>
      state = state.copyWith(draft: state.draft.copyWith(gymId: value));

  void updateExperienceLevel(ExperienceLevel value) => state = state.copyWith(
        draft: state.draft.copyWith(experienceLevel: value),
      );

  void updateGender(Gender value) =>
      state = state.copyWith(draft: state.draft.copyWith(gender: value));

  void updateBodyWeightKg(double? value) =>
      state = state.copyWith(draft: state.draft.copyWith(bodyWeightKg: value));

  void updateHeightCm(int? value) =>
      state = state.copyWith(draft: state.draft.copyWith(heightCm: value));

  // ---------- Submit ----------

  /// Persiste el draft a Firestore via `UserRepository.update`.
  ///
  /// Normalmente el doc `users/{uid}` ya existe (lo crea
  /// `AuthService.signUpWithEmail` via `getOrCreate`). Pero una sesión
  /// restaurada (la app reabre con login cacheado) NUNCA corre
  /// `createIfAbsent` — sólo lo hace un sign-in/sign-up explícito — así que una
  /// cuenta cuyos docs nunca se crearon, o se borraron (típico en dev), llega
  /// acá sin `users/{uid}`. En ese caso `update()` hace un merge que, sobre el
  /// doc inexistente, se evalúa como CREATE y las firestore.rules lo deniegan
  /// (el partial sanitizado no lleva `uid`/`role`). Por eso garantizamos el doc
  /// base ANTES del update con `createIfAbsent` (idempotente: corta solo si ya
  /// existe).
  ///
  /// Si hay avatar local, lo subimos primero a Firebase Storage y guardamos
  /// la URL resultante. Si el upload falla (ej. bucket no creado en Console
  /// todavía), persistimos el resto del perfil y dejamos avatarUrl null — el
  /// atleta puede reintentar desde Perfil → Ajustes más adelante.
  Future<void> submit() async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) {
      state = state.copyWith(
        submitError: StateError('No authenticated user'),
      );
      return;
    }
    final uid = user.uid;
    state = state.copyWith(isSubmitting: true, clearSubmitError: true);

    String? avatarUrl;
    final localPath = state.draft.avatarLocalPath;
    if (localPath != null) {
      try {
        avatarUrl =
            await ref.read(avatarUploadServiceProvider).upload(localPath);
      } on FirebaseException {
        avatarUrl = null;
      } catch (_) {
        avatarUrl = null;
      }
    }

    try {
      final repo = ref.read(userRepositoryProvider);
      // Self-heal: garantiza que users/{uid} + userPublicProfiles/{uid} existan
      // antes del update parcial (ver doc de submit). Idempotente.
      await repo.createIfAbsent(uid: uid, email: user.email ?? '');

      final draft = state.draft;
      final partial = <String, Object?>{
        'displayName': draft.username?.trim(),
        'gymId': draft.gymId == kNoGymId ? null : draft.gymId,
        'experienceLevel': draft.experienceLevel?.toJson(),
        'gender': draft.gender?.toJson(),
        'bodyWeightKg': draft.bodyWeightKg,
        'heightCm': draft.heightCm,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };
      await repo.update(uid, partial);
      state = state.copyWith(isSubmitting: false);
    } catch (e) {
      state = state.copyWith(isSubmitting: false, submitError: e);
      rethrow;
    }
  }
}
