import '../../profile/data/user_repository.dart';
import '../domain/onboarding_seen.dart';
import '../domain/onboarding_surface.dart';

/// Persiste el flag de onboarding en `users/{uid}.onboardingSeen` (issue #627).
///
/// Delega en [UserRepository.update] en vez de escribir Firestore directo, así
/// hereda gratis el filtro de campos inmutables, el `updatedAt` y —sobre
/// todo— la política de dual-write. `onboardingSeen` NO está en los subsets
/// público ni de trainer, así que este write toca UN solo doc: `users/{uid}`.
/// Eso importa para las rules: los allowlists `hasOnly` viven en
/// `userPublicProfiles` / `trainerPublicProfiles`, docs que este write ni
/// roza (trap clase-#563 evitado por construcción, no por suerte).
class OnboardingRepository {
  OnboardingRepository({required UserRepository users}) : _users = users;

  final UserRepository _users;

  /// Nombre del campo en el doc. Fuente única para tests y rules.
  static const String fieldName = 'onboardingSeen';

  /// Marca [surface] como vista en su versión actual y devuelve el mapa
  /// resultante.
  ///
  /// [current] es el estado que ya tiene el perfil en memoria: lo mergeamos
  /// nosotros en vez de mandar sólo la clave nueva porque así el valor que
  /// devolvemos es exactamente lo que quedó persistido, sin releer el doc.
  Future<OnboardingSeen> markSeen({
    required String uid,
    required OnboardingSeen current,
    required OnboardingSurface surface,
  }) =>
      _write(uid: uid, next: current.markSeen(surface));

  /// Vuelve [surface] a "nunca vista" — el entry point de "re-ver el tour".
  Future<OnboardingSeen> reset({
    required String uid,
    required OnboardingSeen current,
    required OnboardingSurface surface,
  }) =>
      _write(uid: uid, next: current.reset(surface));

  Future<OnboardingSeen> _write({
    required String uid,
    required OnboardingSeen next,
  }) async {
    await _users.update(uid, {fieldName: next.toJson()});
    return next;
  }
}
