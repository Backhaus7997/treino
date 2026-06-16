import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/domain/user_profile.dart';

/// Greeting + avatar header for the Home screen.
/// Receives [UserProfile?] by parameter — no provider reads (REQ-HOME-SCREEN-001).
/// null profile triggers the "HOLA!" fallback branch (REQ-HOME-HEADER-002/004).
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.profile});

  final UserProfile? profile;

  static String _computeInitials(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '?';
    return displayName.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final displayName = profile?.displayName;
    final avatarUrl = profile?.avatarUrl;

    final greetingText = (displayName != null && displayName.isNotEmpty)
        ? 'HOLA, ${displayName.toUpperCase()}!'
        : 'HOLA!';

    final initials = _computeInitials(displayName);

    final Widget avatarWidget = Semantics(
      image: true,
      label: (displayName != null && displayName.isNotEmpty)
          ? l10n.a11yAvatarLabel(displayName)
          : l10n.a11yAvatarLabelGeneric,
      child: SizedBox(
        width: 56,
        height: 56,
        child: ClipOval(
          child: avatarUrl != null
              ? CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _AvatarFallback(
                    initials: initials,
                    palette: palette,
                  ),
                  errorWidget: (_, __, ___) => _AvatarFallback(
                    initials: initials,
                    palette: palette,
                  ),
                )
              : _AvatarFallback(initials: initials, palette: palette),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            greetingText,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 0.8,
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        avatarWidget,
      ],
    );
  }
}

/// Private circular avatar fallback with gradient fill and initials text.
class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials, required this.palette});

  final String initials;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accent, palette.highlight],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: palette.bg,
        ),
      ),
    );
  }
}
