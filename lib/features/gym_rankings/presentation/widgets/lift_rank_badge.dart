import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/lift_rank.dart';

/// La insignia de un [LiftRank]: un hexágono con una barra que lleva un disco
/// más por lado a medida que sube el rango. Los SVG los genera
/// `tool/build_lift_rank_badges.dart`.
///
/// Es DECORATIVA para los lectores de pantalla: el rango no depende del color
/// ni del dibujo, siempre va acompañado de su nombre en texto (la franja "Tu
/// rango") o dentro de la etiqueta de la fila. Por eso no expone semántica
/// propia.
///
/// Los SVG de rango son multicolor con materiales fijos (bronce, plata, oro…) y
/// NO se tiñen — `treino_logo.dart` tiñe de un solo color con `srcIn`, y acá eso
/// los dejaría en una silueta plana. La única excepción es `none`
/// ("sin rango"): un contorno de un solo color que sí toma `textMuted`.
class LiftRankBadge extends StatelessWidget {
  const LiftRankBadge({super.key, required this.rank, this.size = rowSize});

  final LiftRank rank;

  /// Lado del cuadrado donde se dibuja la insignia.
  final double size;

  /// Tamaño en una fila de ranking. A este tamaño el marco se simplifica solo
  /// y se lee por silueta y color.
  static const double rowSize = 28;

  /// Tamaño en la franja "Tu rango".
  static const double featuredSize = 56;

  @override
  Widget build(BuildContext context) {
    final muted = rank == LiftRank.none;
    return ExcludeSemantics(
      child: SvgPicture.asset(
        rank.assetPath,
        width: size,
        height: size,
        colorFilter: muted
            ? ColorFilter.mode(
                AppPalette.of(context).textMuted, BlendMode.srcIn)
            : null,
      ),
    );
  }
}
