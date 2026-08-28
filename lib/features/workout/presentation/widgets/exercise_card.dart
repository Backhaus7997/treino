import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Collapsible presentation shell for one exercise in the routine editor.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.menu,
    required this.child,
    this.hasError = false,
    super.key,
  });

  final String title;
  final Widget summary;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget menu;
  final Widget child;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child:
              Icon(TreinoIcon.dragHandle, size: 18, color: palette.textFaint),
        ),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s12,
              AppSpacing.s12,
              AppSpacing.s8,
            ),
            decoration: BoxDecoration(
              color: palette.bg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color:
                    hasError ? palette.danger.withAlpha(128) : palette.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: const Key('exercise_card_header'),
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.hairline,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.barlow(
                                  fontSize: 16,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.hairline),
                              summary,
                            ],
                          ),
                        ),
                      ),
                      menu,
                    ],
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: AppSpacing.s12),
                  // La key existe SOLO cuando la card está desplegada: es lo
                  // que deja a un test saber en qué estado está sin depender
                  // del contenido. Ver `expandirEjercicios` en los fixtures.
                  KeyedSubtree(
                    key: const Key('exercise_card_body'),
                    child: child,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
