import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_count_up.dart';

/// Reusable stat tile — label above, value below.
/// Used in both [RoutineDetailScreen] and [ExerciseDetailScreen].
/// [value] accepts null and renders "—" as a placeholder (Fase 2 state).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.countUpValue,
    this.countUpFormatter,
  });

  final String label;
  final String? value;

  /// Si no-null, el número se cuenta 0 → [countUpValue] al montarse
  /// (TreinoCountUp) en vez de mostrar [value] estático — para el momento de
  /// éxito del resumen post-entreno. `null` (default) → comportamiento sin
  /// cambios: [value] estático o "—".
  final num? countUpValue;

  /// Formatea [countUpValue] mientras cuenta (mismo contrato que
  /// [TreinoCountUp.formatter]). Ignorado si [countUpValue] es null.
  final String Function(num value)? countUpFormatter;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final valueStyle = GoogleFonts.barlowCondensed(
      fontWeight: FontWeight.w700,
      fontSize: 22,
      color: palette.textPrimary,
    );
    final countUpValue = this.countUpValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        countUpValue == null
            ? Text(value ?? '—', style: valueStyle)
            : TreinoCountUp(
                value: countUpValue,
                formatter: countUpFormatter,
                style: valueStyle,
              ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
