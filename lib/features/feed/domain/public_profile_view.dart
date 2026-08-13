import 'package:freezed_annotation/freezed_annotation.dart';

import 'follow.dart';

part 'public_profile_view.freezed.dart';

/// View-model for the public profile screen. Composes denormalized author
/// data (from any `Post` by the target) with the viewer↔target follow state
/// and a self-visit flag.
///
/// **DOS aristas, no una relación.** Antes esto era un solo `Friendship?`, y
/// por eso el perfil no podía distinguir "yo lo sigo" de "él me sigue": eran el
/// mismo documento. Los cuatro estados posibles entre dos usuarios salen de
/// combinar los dos campos de abajo, y cada botón de la pantalla mira el que le
/// corresponde:
///
/// - el botón SEGUIR/SIGUIENDO/SOLICITUD/ACEPTAR y el gate de privacidad del
///   perfil miran la arista **saliente** (¿yo lo sigo?);
/// - el botón MENSAJE mira la **entrante** (¿él me sigue?), porque abrir un
///   chat es poder mandar el primer mensaje y eso requiere que el destinatario
///   me siga (REQ-FOLLOW-012). No es el OR de las dos.
///
/// Not serialized — internal view-model only. No fromJson/toJson.
@freezed
class PublicProfileView with _$PublicProfileView {
  const factory PublicProfileView({
    required String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,

    /// `follows/{viewer}_{target}` — ¿el que mira sigue al del perfil?
    required Follow? outgoingFollow,

    /// `follows/{target}_{viewer}` — ¿el del perfil sigue al que mira?
    required Follow? incomingFollow,
    required bool isSelf,
    int? workoutsCount,
    int? racha,
    int? followersCount,
    int? followingCount,
    // Target profile visibility. Mirrors `UserPublicProfile.isProfilePublic`
    // for the target user. Default `true` matches the model default so
    // unauthenticated / missing-profile branches behave as pre-existing code.
    @Default(true) bool isPublic,
  }) = _PublicProfileView;
}
