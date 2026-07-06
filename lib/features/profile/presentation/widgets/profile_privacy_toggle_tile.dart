import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/application/auth_providers.dart';
import '../../application/user_public_profile_providers.dart';
import 'profile_section_tile.dart';

/// PRIVACIDAD section tile — flips `UserPublicProfile.isProfilePublic`.
///
/// UX model (Instagram-style):
/// - Public (default): anyone can see your feed / stats / rutinas; new
///   follow requests are auto-accepted.
/// - Private: only the identity header stays visible to non-followers;
///   detailed content is gated until you accept their request.
///
/// Existing `accepted` friendships are NOT affected by flipping this flag
/// (Option X of the privacy scope discussion) — the change only shapes
/// how NEW requests are handled from now on.
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
          onChanged: uid.isEmpty || _busy
              ? null
              : (v) => _onChanged(uid, v),
          activeThumbColor: palette.accent,
        ),
      ),
    );
  }
}
