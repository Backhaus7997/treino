import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/tokens/components/treino_empty_state_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../preview_wrapper.dart';

/// Previews del kit — Finding W3.
@Preview(name: 'EmptyState — normal', wrapper: coachHubPreviewWrapper)
Widget emptyStatePreview() => TreinoEmptyState(
      icon: TreinoIcon.emptyState,
      title: 'Sin alumnos todavía',
      description: 'Invitá a tu primer alumno para empezar.',
      ctaLabel: 'Invitar alumno',
      onCtaTap: () {},
    );

@Preview(name: 'EmptyState — loading', wrapper: coachHubPreviewWrapper)
Widget emptyStateLoadingPreview() => const TreinoEmptyState(
      icon: TreinoIcon.emptyState,
      title: '',
      loading: true,
    );

/// Estado vacío genérico del kit Coach Hub Web — Fase 1.
///
/// Ícono + título + descripción opcional + CTA opcional. Se usa en el shell
/// y en el resto de secciones (Fases 2-12) cuando no hay datos disponibles.
///
/// Estados:
/// - Normal: ícono + título + descripción.
/// - Con CTA: botón de acción debajo del contenido.
/// - Loading: skeleton shimmer.
///
/// Entrada animada vía [TreinoFadeSlideIn] (REQ-SH-010).
/// Tokens: [TreinoEmptyStateTokens.of(context)] — nunca hex inline.
///
/// Uso:
/// ```dart
/// TreinoEmptyState(
///   icon: TreinoIcon.emptyState,
///   title: 'Sin alumnos todavía',
///   description: 'Invitá a tu primer alumno para empezar.',
///   ctaLabel: 'Invitar alumno',
///   onCtaTap: () => nav.push('/alumnos/invitar'),
/// )
/// ```
class TreinoEmptyState extends StatelessWidget {
  const TreinoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.ctaLabel,
    this.onCtaTap,
    this.loading = false,
  });

  /// Ícono decorativo del estado vacío.
  final IconData icon;

  /// Título principal.
  final String title;

  /// Descripción opcional debajo del título.
  final String? description;

  /// Texto del botón de acción. Null = sin CTA.
  final String? ctaLabel;

  /// Callback del botón de acción. Ignorado si [ctaLabel] es null.
  final VoidCallback? onCtaTap;

  /// `true` mientras se cargan los datos — muestra skeleton.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _SkeletonContent();
    }

    final tokens = TreinoEmptyStateTokens.of(context);

    return TreinoFadeSlideIn(
      child: Center(
        child: Padding(
          key: const Key('empty_state_content'),
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: TreinoEmptyStateTokens.iconSize,
                color: tokens.iconColor,
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: tokens.titleColor,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: tokens.descriptionColor,
                  ),
                ),
              ],
              if (ctaLabel != null) ...[
                const SizedBox(height: AppSpacing.s12),
                TextButton(
                  onPressed: onCtaTap,
                  child: Text(
                    ctaLabel!,
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: tokens.ctaColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton de carga para [TreinoEmptyState].
class _SkeletonContent extends StatelessWidget {
  const _SkeletonContent();

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoEmptyStateTokens.of(context);

    return TreinoShimmer(
      child: Center(
        child: Padding(
          key: const Key('empty_state_skeleton'),
          // Composición documentada: s20 + s12 (sin token único de 32 en la
          // escala cerrada — ver AppSpacing).
          padding: const EdgeInsets.all(AppSpacing.s20 + AppSpacing.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: TreinoEmptyStateTokens.iconSize,
                height: TreinoEmptyStateTokens.iconSize,
                decoration: BoxDecoration(
                  color: tokens.iconColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Container(
                width: 160,
                height: 16,
                decoration: BoxDecoration(
                  color: tokens.iconColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
