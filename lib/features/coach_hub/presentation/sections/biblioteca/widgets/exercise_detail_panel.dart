// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import 'exercise_detail_dialog.dart';

/// Ancho del panel lateral de detalle, en px lógicos.
const double kExerciseDetailPanelWidth = 420;

/// Detalle persistente de Biblioteca para el tramo ancho de tres columnas.
///
/// Comparte [ExerciseDetailBody] con el modal; sólo cambia el hospedaje.
class ExerciseDetailPanel extends StatelessWidget {
  const ExerciseDetailPanel({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    required this.onClose,
    this.ownerId,
  });

  final String exerciseId;
  final String exerciseName;
  final String? ownerId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: kExerciseDetailPanelWidth,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s18,
              AppSpacing.s14,
              AppSpacing.s8,
              AppSpacing.s8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    exerciseName,
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      fontSize: 24,
                      fontWeight: AppFonts.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle', // i18n
                  onPressed: onClose,
                  icon: Icon(
                    TreinoIcon.close,
                    color: palette.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.s18),
              child: ExerciseDetailBody(
                exerciseId: exerciseId,
                ownerId: ownerId,
                exerciseName: exerciseName,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
