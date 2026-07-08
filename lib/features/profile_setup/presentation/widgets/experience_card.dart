import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';

/// Card seleccionable de un nivel de experiencia en el step 3.
/// Cuando [selected] = true, border accent. Mockup: `profile-setup-3.png`.
class ExperienceCard extends StatelessWidget {
  const ExperienceCard({
    super.key,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  color: selected ? palette.accent : palette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: GoogleFonts.barlow(
                  color: palette.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
