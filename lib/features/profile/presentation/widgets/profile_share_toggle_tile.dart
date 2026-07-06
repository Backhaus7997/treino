import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../coach/application/profile_share_providers.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../application/user_providers.dart';
import 'profile_section_tile.dart';

/// PRIVACIDAD — "Compartir mis datos con mi entrenador" toggle.
///
/// Lets the athlete opt in/out of sharing their personal profile fields
/// with their active trainer. When opted in, writes a snapshot of the
/// athlete's current [UserProfile] fields to `profile_shares/{athleteId}`.
/// When opted out, deletes the doc.
///
/// Mirrors [ProfilePrivacyToggleTile] exactly in style (same widget type,
/// same [ProfileSectionTile] with trailing [Switch.adaptive], same `_busy`
/// guard, same [SnackBar] on success/error).
///
/// Disabled with a "Vinculáte con un entrenador..." hint when the athlete has
/// no active trainer link. If the athlete has multiple active links (unusual),
/// the first one is used — documented limitation, V2 can add per-trainer grants.
///
/// Known limitation (V2): the shared snapshot is a point-in-time copy; the
/// athlete must toggle OFF then ON to refresh it after editing their profile.
class ProfileShareToggleTile extends ConsumerStatefulWidget {
  const ProfileShareToggleTile({super.key});

  @override
  ConsumerState<ProfileShareToggleTile> createState() =>
      _ProfileShareToggleTileState();
}

class _ProfileShareToggleTileState
    extends ConsumerState<ProfileShareToggleTile> {
  bool _busy = false;

  Future<void> _onChanged(bool newValue) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    // Read everything we need synchronously before any await
    final profile = ref.read(userProfileProvider).valueOrNull;
    final link = await ref.read(currentAthleteLinkProvider.future);
    final repo = ref.read(profileShareRepositoryProvider);

    if (profile == null || link == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      if (newValue) {
        await repo.grant(
          athleteId: profile.uid,
          trainerId: link.trainerId,
          phone: profile.phone,
          bornAt: profile.bornAt,
          heightCm: profile.heightCm,
          bodyWeightKg: profile.bodyWeightKg,
          gender: profile.gender,
          experienceLevel: profile.experienceLevel,
          updatedAt: DateTime.now().toUtc(),
        );
        if (!mounted) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Datos compartidos con tu entrenador.', // i18n: Fase W2
              ),
              duration: Duration(seconds: 2),
            ),
          );
      } else {
        await repo.revoke(profile.uid);
        if (!mounted) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Ya no compartís tus datos con tu entrenador.', // i18n: Fase W2
              ),
              duration: Duration(seconds: 2),
            ),
          );
      }
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos cambiar la configuración. Probá de nuevo.', // i18n: Fase W2
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

    // Read the athlete's own profile — uid + snapshot fields
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final uid = profile?.uid ?? '';

    // Active trainer link — null while loading or if the athlete has no link
    final linkAsync = ref.watch(currentAthleteLinkProvider);
    final activeLink = linkAsync.valueOrNull;

    // Current share state — isSharing iff the doc exists (non-null)
    final isSharing = ref.watch(
      profileShareProvider(uid).select((a) => a.valueOrNull != null),
    );

    // The toggle is disabled until we know for sure the athlete has no link.
    // While loading we also disable to prevent race-condition double-taps.
    final hasLink = activeLink != null;
    final isLoading = linkAsync.isLoading || uid.isEmpty;

    final enabled = hasLink && !isLoading && !_busy;

    final subtitle = hasLink
        ? 'Teléfono, altura, peso, género y nivel.' // i18n: Fase W2
        : 'Vinculáte con un entrenador para compartir tus datos.'; // i18n: Fase W2

    return Semantics(
      button: true,
      toggled: isSharing,
      label: isSharing
          ? 'Compartir datos con entrenador: activado' // i18n: Fase W2
          : 'Compartir datos con entrenador: desactivado', // i18n: Fase W2
      excludeSemantics: true,
      child: ProfileSectionTile(
        icon: TreinoIcon.shieldCheck,
        title: 'Compartir mis datos con mi entrenador', // i18n: Fase W2
        subtitle: subtitle,
        inGroup: true,
        onTap: () {
          if (!enabled) return;
          _onChanged(!isSharing);
        },
        trailing: Switch.adaptive(
          value: isSharing,
          onChanged: enabled ? (v) => _onChanged(v) : null,
          activeThumbColor: palette.accent,
        ),
      ),
    );
  }
}
