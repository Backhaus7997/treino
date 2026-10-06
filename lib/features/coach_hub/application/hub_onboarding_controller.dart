import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/domain/trainer_location.dart';
import '../../coach/domain/trainer_specialty.dart';
import '../../profile/application/user_providers.dart';
import '../../profile_setup/application/terms_consent_provider.dart';
import '../../profile_setup/application/terms_stamp.dart';
import '../../profile_setup/domain/profile_setup_validators.dart';
import '../domain/perfil_pf_validators.dart';

/// Lo que el paso `pf` del onboarding le pide al PF. Ya viene validado por la
/// pantalla, pero [HubOnboardingController.guardarPerfilPf] lo revalida: la
/// escritura no confía en que la UI haya hecho su trabajo.
class PerfilPfDraft {
  const PerfilPfDraft({
    required this.bio,
    required this.specialty,
    required this.monthlyRate,
    required this.offersOnline,
    required this.locations,
  });

  final String bio;
  final TrainerSpecialty specialty;
  final int monthlyRate;
  final bool offersOnline;
  final List<TrainerLocation> locations;
}

/// Escrituras del onboarding del PF promovido en el Coach Hub (#1331).
///
/// Cada método hace UNA escritura por `UserRepository.update` (un batch que
/// además espeja a los perfiles públicos), nunca toca `role` ni `username`, y
/// deja el resultado en `state`: `AsyncError` si algo falló (validación,
/// moderación, servidor), nunca un `AsyncLoading` colgado. Nadie navega desde
/// acá: la etapa se recalcula sobre el perfil vivo y el router decide.
class HubOnboardingController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Paso `age`: solo `bornAt`. El piso de 13 años se valida acá primero; las
  /// rules (`bornAtOk`/`bornAtKept`) siguen siendo la última defensa.
  Future<void> guardarEdad(DateTime bornAt) => _ejecutar(() async {
        if (ProfileSetupValidators.validateBornAt(bornAt) != null) {
          throw StateError('born-at-invalid');
        }
        await ref
            .read(userRepositoryProvider)
            .update(_uid(), <String, Object?>{'bornAt': bornAt});
      });

  /// Paso `identity`: nombre, apellido, `displayName` derivado y, solo si
  /// falta evidencia, el estampado de términos, todo en UNA escritura.
  Future<void> guardarIdentidad({
    required String nombre,
    required String apellido,
    required bool aceptoTerminos,
  }) =>
      _ejecutar(() async {
        final first = nombre.trim();
        final last = apellido.trim();
        if (first.isEmpty || last.isEmpty) {
          throw StateError('name-required');
        }
        final uid = _uid();
        final repo = ref.read(userRepositoryProvider);

        // Misma pregunta y misma defensa que el alta de mobile
        // (`profile_setup_notifier.dart`): lo observado puede ser caché, así
        // que si no dice «ya hay evidencia» se confirma contra el SERVIDOR.
        // Si esa consulta falla, la excepción corta acá: no se estampa
        // consentimiento sobre un dato que no se pudo confirmar.
        final estampar = await needsTermsStamp(
          observedHasEvidence: ref.read(termsConsentRequiredProvider) == false,
          acceptedAtFromServer: () async =>
              (await repo.getFromServer(uid))?.termsAcceptedAt,
        );
        if (estampar && !aceptoTerminos) {
          throw StateError('terms-not-accepted');
        }

        await repo.update(uid, <String, Object?>{
          'firstName': first,
          'lastName': last,
          // Igual que `cuenta_tab.dart`: nombre + apellido, sin blancos.
          'displayName': [first, last].where((s) => s.isNotEmpty).join(' '),
          if (estampar) ...termsStampFields(),
        });
      });

  /// Paso `pf`: bio, especialidad, tarifa y modalidad. El partial lleva
  /// `displayName` a propósito (D8): sin él `trainerPublicProfiles` nacería
  /// sin nombre y el PF quedaría fuera de `orderBy('displayNameLowercase')`.
  ///
  /// [otorgaConsentimientoUbicacion] viaja en el MISMO batch (P1-d): la
  /// pantalla pregunta antes y decide; el controller solo lo escribe.
  Future<void> guardarPerfilPf(
    PerfilPfDraft d, {
    required bool otorgaConsentimientoUbicacion,
  }) =>
      _ejecutar(() async {
        final errorBio = validarBio(d.bio);
        if (errorBio != null) throw ArgumentError(errorBio);
        final errorPrecio = validarPrecio(d.monthlyRate.toString());
        if (errorPrecio != null) throw ArgumentError(errorPrecio);
        if (!d.offersOnline && d.locations.isEmpty) {
          throw StateError('modality-required');
        }
        final perfil = ref.read(userProfileProvider).valueOrNull;
        final displayName = perfil?.displayName?.trim() ?? '';
        if (displayName.isEmpty) throw StateError('display-name-missing');

        await ref.read(userRepositoryProvider).update(
              _uid(),
              <String, Object?>{
                'displayName': displayName,
                'trainerBio': d.bio.trim(),
                'trainerSpecialty': TrainerSpecialtyX.toWire(d.specialty),
                'trainerMonthlyRate': d.monthlyRate,
                'trainerOffersOnline': d.offersOnline,
                'trainerLocations': d.locations.map((l) => l.toJson()).toList(),
                // Un lugar `stale` ya no se publica: no entra a la búsqueda.
                'trainerGeohashes': d.locations
                    .where((l) => l.stale != true)
                    .map((l) => l.geohash)
                    .toSet()
                    .toList(),
              },
              grantLocationConsent: otorgaConsentimientoUbicacion,
            );
      });

  String _uid() {
    final uid = ref.read(userProfileProvider).valueOrNull?.uid;
    if (uid == null) throw StateError('no-profile');
    return uid;
  }

  Future<void> _ejecutar(Future<void> Function() escribir) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(escribir);
  }
}

final hubOnboardingControllerProvider =
    AsyncNotifierProvider<HubOnboardingController, void>(
  HubOnboardingController.new,
);
