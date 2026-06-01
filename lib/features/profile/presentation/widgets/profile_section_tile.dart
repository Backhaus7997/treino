import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// A reusable row tile used in the CUENTA section and the Settings screen.
///
/// Renders an icon, title, optional subtitle, and a trailing widget (chevron
/// by default). Supports a [destructive] mode that tints the icon and title
/// in [AppPalette.danger].
///
/// All colors come from [AppPalette] — no hex literals. // i18n: Fase 6 Etapa 3
class ProfileSectionTile extends StatelessWidget {
  const ProfileSectionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.destructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Optional override for the trailing widget. Defaults to a chevron icon.
  final Widget? trailing;

  /// When [true], tints the icon and title in [AppPalette.danger].
  final bool destructive;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final iconColor = destructive ? palette.danger : palette.accent;
    final titleColor = destructive ? palette.danger : palette.textPrimary;

    // Mockup parity 2026-06-01 polish pass:
    //   - Tighter vertical gap between tiles (4 vs 6)
    //   - Icon wrapped in a soft circular background (subtle accent-tinted
    //     circle, mirrors the mockup's icon treatment)
    //   - Internal vertical padding nudged down to keep tiles more compact
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.textMuted.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title, // i18n: Fase 6 Etapa 3
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!, // i18n: Fase 6 Etapa 3
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    TreinoIcon.chevronRight,
                    size: 16,
                    color: palette.textMuted,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
