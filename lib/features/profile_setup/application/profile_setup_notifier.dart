import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart' show firebaseAuthProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../profile/domain/gender.dart';
import '../domain/gym.dart';
import '../domain/profile_setup_draft.dart';
import '../domain/profile_setup_validators.dart';
import 'profile_setup_providers.dart' show avatarUploadServiceProvider;

/// Estado de la verificación async de disponibilidad del username (handle
/// público) en step 1. El handle se persiste como `displayName` y se renderiza
/// como `@handle` en perfiles públicos, así que tiene que ser único.
enum UsernameAvailability {
  /// Aún no se verificó (campo vacío o formato inválido).
  unknown,

  /// Verificación async en curso (query a Firestore con debounce).
  checking,

  /// El handle está libre — se puede avanzar.
  available,

  /// Otro usuario ya tiene ese handle.
  taken,

  /// La query falló (red / permisos). No bloquea de forma silenciosa: la UI
  /// muestra un mensaje y submit revalida.
  error,
}

/// Estado in-memory del flow: el draft del usuario + el step actual (0..3) +
/// flags de submit (loading / error).
class ProfileSetupState {
  const ProfileSetupState({
    required this.draft,
    required this.currentStep,
    this.isSubmitting = false,
    this.submitError,
    this.usernameAvailability = UsernameAvailability.unknown,
  });

  final ProfileSetupDraft draft;
  final int currentStep;
  final bool isSubmitting;
  final Object? submitError;

  /// Resultado de la verificación de disponibilidad del username (step 1).
  final UsernameAvailability usernameAvailability;

  ProfileSetupState copyWith({
    ProfileSetupDraft? draft,
    int? currentStep,
    bool? isSubmitting,
    Object? submitError,
    bool clearSubmitError = false,
    UsernameAvailability? usernameAvailability,
  }) =>
      ProfileSetupState(
        draft: draft ?? this.draft,
        currentStep: currentStep ?? this.currentStep,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        submitError:
            clearSubmitError ? null : (submitError ?? this.submitError),
        usernameAvailability: usernameAvailability ?? this.usernameAvailability,
      );

  static const total = 4;

  // Step 1 sólo deja avanzar con username de formato válido Y verificado como
  // disponible — `displayName` es el handle público y tiene que ser único.
  // `error` deja pasar (no bloquea por una falla de red); submit revalida.
  bool get canGoNext => switch (currentStep) {
        0 => draft.isStep1Valid &&
            (usernameAvailability == UsernameAvailability.available ||
                usernameAvailability == UsernameAvailability.error),
        1 => draft.isStep2Valid,
        2 => draft.isStep3Valid,
        3 => draft.isStep4Valid,
        _ => false,
      };

  bool get isLastStep => currentStep == total - 1;
}

class ProfileSetupNotifier extends Notifier<ProfileSetupState> {
  /// Debounce de la verificación async de disponibilidad del username, para no
  /// pegarle a Firestore en cada tecla.
  Timer? _usernameDebounce;

  /// Monotónico: cada llamada a [_runUsernameCheck] incrementa este token y
  /// sólo aplica su resultado si sigue siendo el último. Evita que una
  /// respuesta lenta de un username viejo pise a una más nueva (race).
  int _usernameCheckToken = 0;

  @override
  ProfileSetupState build() {
    ref.onDispose(() => _usernameDebounce?.cancel());
    return const ProfileSetupState(
      draft: ProfileSetupDraft(),
      currentStep: 0,
    );
  }

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

  /// Actualiza el username del draft y dispara la verificación de
  /// disponibilidad con debounce. Mientras el formato no sea válido, la
  /// disponibilidad queda en `unknown` (no tiene sentido consultar Firestore).
  void updateUsername(String value) {
    state = state.copyWith(draft: state.draft.copyWith(username: value));

    _usernameDebounce?.cancel();
    final trimmed = value.trim();

    // Formato inválido → no consultamos. El validator del campo ya muestra el
    // error de formato; reseteamos a `unknown` para que no quede un estado
    // verde/rojo viejo.
    if (ProfileSetupValidators.validateUsername(value) != null) {
      // Token nuevo así descartamos cualquier check en vuelo.
      _usernameCheckToken++;
      if (state.usernameAvailability != UsernameAvailability.unknown) {
        state = state.copyWith(
          usernameAvailability: UsernameAvailability.unknown,
        );
      }
      return;
    }

    // Formato válido → mostramos "verificando" ya y consultamos con debounce.
    state = state.copyWith(
      usernameAvailability: UsernameAvailability.checking,
    );
    _usernameDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _runUsernameCheck(trimmed),
    );
  }

  /// Consulta a Firestore si el handle [username] ya está tomado por OTRO
  /// usuario. Usa un token monotónico para ignorar respuestas obsoletas.
  Future<void> _runUsernameCheck(String username) async {
    final token = ++_usernameCheckToken;
    try {
      final excludeUid = ref.read(firebaseAuthProvider).currentUser?.uid;
      final taken = await ref
          .read(userPublicProfileRepositoryProvider)
          .isDisplayNameTaken(username, excludeUid: excludeUid);
      if (token != _usernameCheckToken) return; // respuesta obsoleta
      state = state.copyWith(
        usernameAvailability:
            taken ? UsernameAvailability.taken : UsernameAvailability.available,
      );
    } catch (_) {
      if (token != _usernameCheckToken) return;
      state = state.copyWith(
        usernameAvailability: UsernameAvailability.error,
      );
    }
  }

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
      final draft = state.draft;
      final handle = draft.username?.trim() ?? '';

      // Revalidación de unicidad en el último submit (red de seguridad sobre el
      // check con debounce de step 1): nunca persistimos un handle duplicado en
      // silencio. Si otro usuario lo tomó entre el check y el submit, marcamos
      // `taken` y abortamos — la UI ya muestra "Ese username ya está en uso".
      final taken = await ref
          .read(userPublicProfileRepositoryProvider)
          .isDisplayNameTaken(handle, excludeUid: uid);
      if (taken) {
        // Marcamos `taken` (lo refleja la UI si el usuario vuelve a step 1) y
        // lanzamos para que la pantalla muestre un error en vez de fallar en
        // silencio. Es una carrera rara: el gate de SIGUIENTE ya bloquea un
        // handle tomado en step 1; sólo se llega acá si otro lo reclamó después.
        state = state.copyWith(
          isSubmitting: false,
          usernameAvailability: UsernameAvailability.taken,
        );
        throw StateError('username-taken');
      }

      final repo = ref.read(userRepositoryProvider);
      // Self-heal: garantiza que users/{uid} + userPublicProfiles/{uid} existan
      // antes del update parcial (ver doc de submit). Idempotente.
      await repo.createIfAbsent(uid: uid, email: user.email ?? '');

      final partial = <String, Object?>{
        'displayName': handle,
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
