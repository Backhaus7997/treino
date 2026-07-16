import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';

/// Breadcrumb del detalle de Alumno: «‹ Alumnos / {nombre}» — Fase 3 WU-04.
///
/// Extraído de `_BackLink` (`alumno_detail_screen.dart`, ADR-A3-04). El link
/// «Alumnos» navega de vuelta al roster (`/alumnos`) vía [TreinoTappable]
/// (reemplaza el `GestureDetector` original — mismo criterio que el resto del
/// kit v2). El segmento con el nombre del alumno solo aparece cuando ya se
/// resolvió el perfil (data-honest, ADR-A3-01): mientras carga, el breadcrumb
/// muestra únicamente el link «Alumnos».
class AlumnoBreadcrumb extends StatelessWidget {
  const AlumnoBreadcrumb({super.key, required this.palette, this.athleteName});

  final AppPalette palette;

  /// Nombre del alumno ya resuelto. `null` mientras el perfil está cargando.
  final String? athleteName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TreinoTappable(
          onTap: () => context.go('/alumnos'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TreinoIcon.chevronLeft, size: 16, color: palette.textMuted),
              const SizedBox(width: AppSpacing.hairline),
              Text(
                'Alumnos', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (athleteName != null && athleteName!.isNotEmpty) ...[
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.hairline),
            child: Text(
              '/',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
          Text(
            athleteName!,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
