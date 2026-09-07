// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import 'exercise_detail_dialog.dart';

/// Ancho mínimo del drawer, en px lógicos.
///
/// El ancho pedido es un cuarto de la pantalla, pero en un desktop chico ese
/// cuarto se vuelve una banda ilegible: 320 es el piso donde el video y los
/// pasos de técnica todavía entran.
const double kExerciseDetailPanelMinWidth = 320;

/// Detalle de Biblioteca como drawer SUPERPUESTO, desplegado desde la derecha.
///
/// Superpuesto y no en fila: asi abrir el detalle no le roba ancho a la grilla
/// y las cuatro columnas se sostienen en cualquier desktop. La version anterior
/// vivia en el `Row` y por eso necesitaba una seccion de 1528 px — un umbral
/// que una notebook de 14 pulgadas no alcanza nunca, o sea que el panel no
/// aparecia justo en la maquina donde se mira el producto.
///
/// No lleva scrim ni barrera: el loop del PF es "miro la grilla → abro uno →
/// abro el siguiente", y una barrera modal lo corta en cada iteración. Es la
/// misma lección del #860 con el picker del editor de rutinas.
///
/// Comparte [ExerciseDetailBody] con el modal; sólo cambia el hospedaje.
class ExerciseDetailPanel extends StatelessWidget {
  const ExerciseDetailPanel({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    required this.onClose,
    required this.width,
    this.ownerId,
  });

  final String exerciseId;
  final String exerciseName;
  final String? ownerId;
  final VoidCallback onClose;

  /// Ancho del drawer. Lo calcula el host como un cuarto del ancho disponible,
  /// con piso en [kExerciseDetailPanelMinWidth].
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border(left: BorderSide(color: palette.border)),
        // Superpuesto: sin sombra se lee como una columna mas del layout y no
        // como algo que esta ENCIMA.
        boxShadow: [
          BoxShadow(
            color: palette.scrimDark.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(-8, 0),
          ),
        ],
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
