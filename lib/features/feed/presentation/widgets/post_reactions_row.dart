import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/reaction_providers.dart';
import '../../domain/reaction_type.dart';

/// Compact, always-visible reaction controls for a feed post.
///
/// Loading and provider failures deliberately degrade to zero counts and no
/// selected reaction. A reaction failure must never hide or break the post.
class PostReactionsRow extends ConsumerWidget {
  const PostReactionsRow({
    super.key,
    required this.postId,
  });

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts =
        ref.watch(reactionCountsProvider(postId)).valueOrNull ?? const {};
    final selectedType =
        ref.watch(myReactionProvider(postId)).valueOrNull?.type;

    return Row(
      key: const ValueKey('post-reactions-row'),
      children: [
        for (final type in ReactionType.values) ...[
          if (type != ReactionType.like) const SizedBox(width: 8),
          _ReactionButton(
            type: type,
            count: counts[type] ?? 0,
            isSelected: selectedType == type,
            onTap: () => unawaited(
              ref.read(reactionActionsProvider).toggle(
                    postId: postId,
                    type: type,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.type,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final ReactionType type;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = isSelected ? _activeColor(palette, type) : palette.textMuted;
    final l10n = AppL10n.of(context);

    return Semantics(
      key: ValueKey('reaction-${type.name}-semantics'),
      container: true,
      button: true,
      selected: isSelected,
      label: _semanticsLabel(l10n, type, count),
      child: TreinoTappable(
        onTap: onTap,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _iconFor(type, filled: isSelected),
                    key: ValueKey('reaction-${type.name}-icon'),
                    size: 20,
                    color: color,
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      key: ValueKey('reaction-${type.name}-count'),
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Contorno cuando el usuario no reaccionó, relleno cuando sí.
///
/// Solo cambiar el color deja un ícono de línea teñido, que se lee como un
/// borde de color y no como una reacción encendida. El par contorno/relleno es
/// lo que hace legible el estado de un vistazo.
IconData _iconFor(ReactionType type, {required bool filled}) => switch (type) {
      ReactionType.like =>
        filled ? TreinoIcon.reactionLikeFill : TreinoIcon.reactionLike,
      ReactionType.fire =>
        filled ? TreinoIcon.reactionFireFill : TreinoIcon.reactionFire,
      ReactionType.clap =>
        filled ? TreinoIcon.reactionClapFill : TreinoIcon.reactionClap,
    };

String _semanticsLabel(AppL10n l10n, ReactionType type, int count) {
  final name = switch (type) {
    ReactionType.like => l10n.a11yReactionLike,
    ReactionType.fire => l10n.a11yReactionFire,
    ReactionType.clap => l10n.a11yReactionClap,
  };
  return '$name, ${l10n.a11yReactionCount(count)}';
}

Color _activeColor(AppPalette palette, ReactionType type) => switch (type) {
      ReactionType.like => palette.reactionLike,
      ReactionType.fire => palette.reactionFire,
      ReactionType.clap => palette.reactionClap,
    };
