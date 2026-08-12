import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/domain/user_role.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_seen.dart';
import '../domain/onboarding_surface.dart';

/// Ruta del tour del ALUMNO en mobile (slice 1).
const String kAthleteOnboardingRoute = '/onboarding/athlete';

/// Prefijo común de TODAS las rutas de onboarding. El gate del router lo usa
/// como loop-guard, así que la ruta del PF mobile (slice 2) queda cubierta sin
/// tocar de nuevo `authRedirect`.
const String kOnboardingRoutePrefix = '/onboarding';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(users: ref.watch(userRepositoryProvider)),
);

/// Flag de onboarding del usuario actual. [OnboardingSeen.empty] mientras el
/// perfil carga o si no hay sesión.
final onboardingSeenProvider = Provider<OnboardingSeen>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  return profile?.onboardingSeen ?? OnboardingSeen.empty;
});

/// Escape hatch de SESIÓN para el gate del router.
///
/// ⚠️  Esta es la lección de #429 hecha código. El flag real vive en Firestore,
/// así que un write fallido (offline, permission-denied) dejaría al usuario
/// encerrado en el tour para siempre: el gate lo seguiría mandando ahí y no
/// habría ninguna salida. Con esto, terminar o saltar el tour SIEMPRE deja
/// salir, se haya persistido o no.
///
/// Es sólo de sesión — se pierde al reiniciar la app. Si el write falló, el
/// tour vuelve a aparecer la próxima vez, que es exactamente lo que le
/// avisamos al usuario con el copy `onboardingSaveError`.
final onboardingDismissedProvider = StateProvider<bool>((ref) => false);

/// Predicado PURO del gate del router — testeable sin widget tree ni
/// `ProviderContainer`, igual que `authRedirect`.
///
/// Slice 1 cubre SÓLO al alumno en mobile. El PF mobile (slice 2) suma acá su
/// propia rama con [OnboardingSurface.trainerMobile]; hasta entonces gatear al
/// PF lo mandaría a una pantalla que todavía no existe.
///
/// `null` (perfil todavía sin cargar) ⇒ `false`: nunca redirigimos a ciegas.
bool athleteOnboardingPending(UserProfile? profile) =>
    profile != null &&
    profile.role == UserRole.athlete &&
    profile.onboardingSeen.isPending(OnboardingSurface.athleteMobile);

/// Versión provider del predicado, para consumidores de UI.
final athleteOnboardingPendingProvider = Provider<bool>((ref) {
  return athleteOnboardingPending(ref.watch(userProfileProvider).valueOrNull);
});

/// Escribe el flag. Vive en `application` porque necesita cruzar el perfil
/// actual (uid + estado del mapa) con el repositorio.
class OnboardingController {
  OnboardingController(this._ref);

  final Ref _ref;

  /// Marca [surface] como vista. Devuelve `true` si el write se persistió.
  ///
  /// ⚠️  NUNCA lanza, y levanta [onboardingDismissedProvider] ANTES de tocar
  /// la red. Es deliberado: el gate del router depende de este flag, y una
  /// excepción propagada —o un write que nunca llega— dejaría al usuario
  /// encerrado en el tour, que es exactamente el bug #429. La UI navega a
  /// /home igual y usa el `false` sólo para avisar que no quedó guardado.
  Future<bool> markSeen(OnboardingSurface surface) async {
    _ref.read(onboardingDismissedProvider.notifier).state = true;
    final profile = _ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return false;
    try {
      await _ref.read(onboardingRepositoryProvider).markSeen(
            uid: profile.uid,
            current: profile.onboardingSeen,
            surface: surface,
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Vuelve [surface] a pendiente — "re-ver el tour". Baja el escape hatch de
  /// sesión, si no el gate seguiría dejándolo pasar de largo.
  Future<bool> reset(OnboardingSurface surface) async {
    _ref.read(onboardingDismissedProvider.notifier).state = false;
    final profile = _ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return false;
    try {
      await _ref.read(onboardingRepositoryProvider).reset(
            uid: profile.uid,
            current: profile.onboardingSeen,
            surface: surface,
          );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final onboardingControllerProvider =
    Provider<OnboardingController>(OnboardingController.new);
