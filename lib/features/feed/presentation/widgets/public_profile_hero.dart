import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_collapsing_top_bar.dart';
import '../../../gyms/application/gym_display_name_provider.dart';
import '../../../gyms/domain/gym.dart' show hasRealGym;
import '../../domain/public_profile_view.dart';
import 'post_avatar.dart';

/// Hero section of the public profile screen. Renders the avatar (96px),
/// uppercase display name, and optional gym subtitle (omitted when the gym
/// is unknown / null / sentinel). Background is a vertical accent→bg gradient.
///
/// DETAIL context (single target user) — resolves the gym name live via
/// [gymDisplayNameProvider] rather than reading a denormalized field, so the name
/// always reflects the current `gyms/` catalog. gyms-foundation Phase 3.
class PublicProfileHero extends ConsumerWidget {
  const PublicProfileHero({super.key, required this.view});

  final PublicProfileView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final gymId = view.authorGymId;
    final gymName = !hasRealGym(gymId)
        ? ''
        : ref.watch(gymDisplayNameProvider(gymId)).valueOrNull ?? '';

    // El gradiente llega hasta el borde superior y la flecha/⋮ de la barra
    // flotan encima (#1559): el avatar arranca debajo de ellos.
    final topInset = TreinoTopBarMetrics.reservedHeightOf(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Se desvanece a transparente, no a `bg` opaco: abajo está el
          // AppBackground (con sus halos), y un `bg` sólido dejaba un corte
          // recto donde terminaba el hero.
          colors: [
            palette.accent.withValues(alpha: 0.18),
            palette.accent.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topInset, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PostAvatar(
              authorDisplayName: view.authorDisplayName,
              authorAvatarUrl: view.authorAvatarUrl,
              size: 96,
            ),
            const SizedBox(height: 14),
            Text(
              view.authorDisplayName.toUpperCase(),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 28,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
            if (gymName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                gymName,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 1.0,
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
