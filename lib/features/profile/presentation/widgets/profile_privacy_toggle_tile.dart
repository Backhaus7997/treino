import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/application/auth_providers.dart';
import '../../application/user_public_profile_providers.dart';
import 'profile_section_tile.dart';

/// PRIVACIDAD section tile — flips `UserPublicProfile.isProfilePublic`.
///
/// Modelo de UX (estilo Instagram):
/// - Público (default): las solicitudes de seguimiento se auto-aceptan.
/// - Privado: las solicitudes nuevas quedan `pending` y las aprobás a mano.
///
/// Las amistades `accepted` que ya existían NO se ven afectadas al flipear el
/// flag (Opción X de la discusión de alcance de privacidad) — el cambio sólo
/// gobierna cómo se tratan las solicitudes NUEVAS de ahí en adelante.
///
/// ⚠️ El flag NO esconde contenido del lado servidor (QA-SEC-011, #778).
/// La versión anterior de este comentario decía que en privado "sólo el header
/// de identidad queda visible para no-seguidores; el contenido detallado queda
/// gateado hasta que aceptes". Era falso: `firestore.rules:942` sirve
/// `userPublicProfiles` entero a cualquier autenticado. Lo que esconde
/// `public_profile_screen.dart` es presentación. El subtítulo que ve el usuario
/// —"Los nuevos seguidores necesitan tu aprobación"— sí describe bien lo que
/// hace el flag, y por eso no cambió. Ver `UserPublicProfile.isProfilePublic`
/// y `docs/security.md` §4.9.
class ProfilePrivacyToggleTile extends ConsumerStatefulWidget {
  const ProfilePrivacyToggleTile({super.key});

  @override
  ConsumerState<ProfilePrivacyToggleTile> createState() =>
      _ProfilePrivacyToggleTileState();
}

class _ProfilePrivacyToggleTileState
    extends ConsumerState<ProfilePrivacyToggleTile> {
  bool _busy = false;

  Future<void> _onChanged(String uid, bool newValue) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(userPublicProfileRepositoryProvider)
          .setProfilePublic(uid, newValue);
      // The stream provider self-updates via .snapshots() — no manual
      // invalidation needed. Snackbar confirms the flip so the user sees
      // an explicit outcome even before the switch re-renders.
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newValue
                  ? 'Perfil público. Cualquiera puede seguirte.' // i18n: Fase W2
                  : 'Perfil privado. Los nuevos seguidores necesitan tu aprobación.', // i18n: Fase W2
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos cambiar la privacidad del perfil.', // i18n: Fase W2
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    // Default true matches UserPublicProfile default — pre-existing docs
    // without the field render as public until the user flips it.
    final isPublic = ref.watch(
      userPublicProfileProvider(uid).select(
        (async) => async.valueOrNull?.isProfilePublic ?? true,
      ),
    );

    return Semantics(
      button: true,
      toggled: isPublic,
      label: isPublic
          ? 'Perfil público' // i18n: Fase W2
          : 'Perfil privado', // i18n: Fase W2
      excludeSemantics: true,
      child: ProfileSectionTile(
        icon: isPublic ? TreinoIcon.globe : TreinoIcon.lock,
        title: 'Perfil público', // i18n: Fase W2
        subtitle: isPublic
            ? 'Cualquiera puede seguirte sin aprobación.' // i18n: Fase W2
            : 'Los nuevos seguidores necesitan tu aprobación.', // i18n: Fase W2
        inGroup: true,
        // The Switch consumes the actual toggle input. Tapping the tile row
        // outside the switch is treated as an intent to flip too.
        onTap: () {
          if (uid.isEmpty || _busy) return;
          _onChanged(uid, !isPublic);
        },
        trailing: Switch.adaptive(
          value: isPublic,
          onChanged: uid.isEmpty || _busy ? null : (v) => _onChanged(uid, v),
          activeThumbColor: palette.accent,
        ),
      ),
    );
  }
}
