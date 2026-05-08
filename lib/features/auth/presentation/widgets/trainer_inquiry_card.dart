import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../auth_strings.dart';

/// Card shown at the bottom of LoginScreen for trainer access inquiry.
/// Tapping opens an AlertDialog with the team email.
class TrainerInquiryCard extends StatelessWidget {
  const TrainerInquiryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: () => _showDialog(context, palette),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(
            color: palette.highlight.withValues(alpha: 0.5),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
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
                    AuthStrings.loginTrainerCardTitle,
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AuthStrings.loginTrainerCardSubtitle,
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
    );
  }

  void _showDialog(BuildContext context, AppPalette palette) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          AuthStrings.trainerInquiryDialogTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          AuthStrings.trainerInquiryDialogBody,
          style: GoogleFonts.barlow(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AuthStrings.trainerInquiryDialogClose),
          ),
        ],
      ),
    );
  }
}
