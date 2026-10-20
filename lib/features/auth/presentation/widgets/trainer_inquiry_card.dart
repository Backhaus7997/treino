import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Card shown at the bottom of WelcomeScreen, LoginScreen and RegisterScreen
/// for trainer access inquiry.
/// Tapping opens an AlertDialog with the team email, unless [onTap] replaces
/// it (WelcomeScreen opens the contact mail directly).
class TrainerInquiryCard extends StatelessWidget {
  const TrainerInquiryCard({super.key, this.onTap});

  /// Acción al tocar. Null = el diálogo con el mail del equipo.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Material + InkWell y no un GestureDetector: además del toque, entra en
    // el foco con Tab y se activa con Enter/Espacio (teclado físico, web,
    // Switch Control), y anuncia el rol de botón.
    return Material(
      color: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: palette.highlight.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => _showDialog(context, palette),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // Shield icon with subtle highlight bg
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.highlight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  TreinoIcon.shieldCheck,
                  color: palette.highlight,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.authLoginTrainerCardTitle,
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.authLoginTrainerCardSubtitle,
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                TreinoIcon.forward,
                color: palette.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, AppPalette palette) {
    final l10n = AppL10n.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          l10n.authTrainerInquiryDialogTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          l10n.authTrainerInquiryDialogBody,
          style: GoogleFonts.barlow(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.authTrainerInquiryDialogClose),
          ),
        ],
      ),
    );
  }
}
