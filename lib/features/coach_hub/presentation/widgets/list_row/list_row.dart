import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/tokens/components/treino_list_row_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../preview_wrapper.dart';
import '../treino_interactive_state.dart';

/// Previews del kit — Finding W3.
@Preview(name: 'ListRow — normal', wrapper: coachHubPreviewWrapper)
Widget listRowPreview() => const TreinoListRow(
      title: 'Ana García',
      subtitle: 'Activo · 12 sesiones',
    );

@Preview(name: 'ListRow — loading', wrapper: coachHubPreviewWrapper)
Widget listRowLoadingPreview() => const TreinoListRow(title: '', loading: true);

/// Fila de lista genérica del kit Coach Hub Web — Fase 1.
///
/// Soporta leading/title/subtitle/trailing slots con estados:
/// - Normal, hover (web), pressed (TreinoTappable), disabled, loading.
/// - Variante dense con altura reducida.
/// - Tokens: TreinoListRowTokens.of(context) — nunca hex inline.
/// - Ambos temas dark y light.
///
/// Uso:
/// ```dart
/// TreinoListRow(
///   leading: CircleAvatar(child: Text('A')),
///   title: 'Ana García',
///   subtitle: 'Activo · 12 sesiones',
///   trailing: const Icon(Icons.chevron_right),
///   onTap: () => nav.push('/alumno/1'),
/// )
/// ```
class TreinoListRow extends StatelessWidget {
  const TreinoListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.loading = false,
    this.dense = false,
  });

  /// Texto principal de la fila.
  final String title;

  /// Texto secundario opcional.
  final String? subtitle;

  /// Widget opcional en el extremo izquierdo (avatar, ícono, etc.).
  final Widget? leading;

  /// Widget opcional en el extremo derecho (chevron, badge, etc.).
  final Widget? trailing;

  /// Acción al tocar la fila. Null = sin interactividad (disabled).
  final VoidCallback? onTap;

  /// `true` mientras se cargan los datos — muestra skeleton shimmer.
  final bool loading;

  /// `true` = variante compacta (padding vertical reducido).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _SkeletonRow(dense: dense);
    }

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        final tokens = TreinoListRowTokens.of(ctx);

        Color bg;
        if (states.disabled) {
          bg = tokens.background;
        } else if (states.hovered || states.pressed) {
          bg = tokens.hoverBackground;
        } else {
          bg = tokens.background;
        }

        final paddingV = dense
            ? TreinoListRowTokens.paddingV / 2
            : TreinoListRowTokens.paddingV;

        return AnimatedContainer(
          duration: AppMotion.resolve(ctx, AppMotion.fast),
          curve: AppMotion.standard,
          color: bg,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: TreinoListRowTokens.paddingH,
              vertical: paddingV,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppFonts.barlow,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: states.disabled
                              ? tokens.disabledColor
                              : tokens.titleColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: states.disabled
                                ? tokens.disabledColor
                                : tokens.subtitleColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton de carga para [TreinoListRow].
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoListRowTokens.of(context);
    final paddingV =
        dense ? TreinoListRowTokens.paddingV / 2 : TreinoListRowTokens.paddingV;

    return TreinoShimmer(
      child: Padding(
        key: const Key('list_row_skeleton'),
        padding: EdgeInsets.symmetric(
          horizontal: TreinoListRowTokens.paddingH,
          vertical: paddingV,
        ),
        child: Row(
          children: [
            // Skeleton del título
            Container(
              width: 140,
              height: 14,
              decoration: BoxDecoration(
                color: tokens.hoverBackground,
                borderRadius:
                    BorderRadius.circular(TreinoListRowTokens.borderRadius / 4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
