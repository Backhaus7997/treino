import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/gym_name.dart';
import '../../domain/public_profile_view.dart';
import 'post_avatar.dart';

/// Hero section of the public profile screen. Renders the avatar (96px),
/// uppercase display name, and optional gym subtitle (omitted when the gym
/// is unknown / null / sentinel). Background is a vertical accent→bg gradient.
class PublicProfileHero extends StatelessWidget {
  const PublicProfileHero({super.key, required this.view});

  final PublicProfileView view;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gymName = gymNameFromId(view.authorGymId);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.accent.withValues(alpha: 0.18),
            palette.bg,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
