import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_count_up.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';

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
    this.icon,
    this.isAccent = false,
    this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final String? value;

  /// Si no-null, el tile se vuelve tappable — para las métricas que son la
  /// puerta a otra pantalla, como los contadores de seguidores del perfil.
  ///
  /// `null` (default) → comportamiento sin cambios: los otros seis usos de
  /// [StatTile] en la app son números y nada más, y no tienen que ganar una
  /// zona tappable ni un nodo de semantics por esto.
  final VoidCallback? onTap;

  /// Etiqueta de accesibilidad del tile tappable. Ignorada si [onTap] es null.
  final String? semanticsLabel;

  /// Ícono opcional de la métrica, a la izquierda del número.
  ///
  /// Cuando es no-null el tile alinea a la izquierda en vez de centrar: con el
  /// contenido centrado, [TreinoCountUp] cambia el ancho del número en cada
  /// tick y empujaría el ícono de un lado a otro mientras cuenta. Anclado a la
  /// izquierda, el ícono queda quieto y sólo crece el número.
  ///
  /// `null` (default) → comportamiento sin cambios: centrado y sin ícono.
  final IconData? icon;

  /// Usa el color de acento para destacar el valor.
  ///
  /// `false` (default) conserva el color primario de todos los usos existentes.
  final bool isAccent;

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
      color: isAccent ? palette.accent : palette.textPrimary,
    );
    final countUpValue = this.countUpValue;
    final icon = this.icon;
    final valueWidget = countUpValue == null
        ? Text(value ?? '—', style: valueStyle)
        : TreinoCountUp(
            value: countUpValue,
            formatter: countUpFormatter,
            style: valueStyle,
          );
    final labelWidget = Text(
      label.toUpperCase(),
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w600,
        fontSize: 10,
        letterSpacing: 1.2,
        color: palette.textMuted,
      ),
    );
    final column = Column(
      crossAxisAlignment:
          icon == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (icon == null)
          valueWidget
        else
          Row(
            children: [
              Icon(icon, size: 15, color: palette.textMuted),
              const SizedBox(width: 8),
              // El ícono ocupa ancho fijo, así que el número se queda con el
              // resto: sin Flexible + scaleDown desborda en pantallas angostas
              // y con font scale de accesibilidad. Mismo patrón que las filas
              // del resumen post-entreno.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: valueWidget,
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        // Sólo la variante con ícono acota el label: la variante centrada
        // (7 pantallas) queda exactamente como estaba.
        if (icon == null)
          labelWidget
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: labelWidget,
          ),
      ],
    );

    final onTap = this.onTap;
    if (onTap == null) return column;

    // `HitTestBehavior.opaque` vía TreinoTappable: el Column deja huecos entre
    // el número y el label, y sin esto el tap se cuela por el medio del tile.
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: TreinoTappable(onTap: onTap, child: column),
    );
  }
}
