import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Card seleccionable de un gym en el step 2. Cuando [selected] = true, border
/// se vuelve accent y aparece un check al final. Inactiva con border normal.
class GymCard extends StatelessWidget {
  const GymCard({
    super.key,
    required this.name,
    required this.address,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String address;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                TreinoIcon.mapPin,
                color: selected ? palette.accent : palette.textMuted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(TreinoIcon.check, color: palette.accent, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
