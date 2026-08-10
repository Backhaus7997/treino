import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/feed_screen_providers.dart';
import '../../domain/feed_segment.dart';
import '../../../../l10n/app_l10n.dart';

/// Margen lateral de la fila de segmentos. Es el mismo 20 que usan el header
/// del feed y el resto del shell: los pills tienen que alinearse con ellos.
const double _kSideMargin = 20;

class FeedSegmentPills extends ConsumerWidget {
  const FeedSegmentPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final segment = ref.watch(feedSegmentProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // El scroll horizontal se queda como red de seguridad —textScale
        // grande, pantallas muy angostas—, pero deja de ser el caso normal:
        // mientras los pills entren, el `minWidth` estira el Row hasta el
        // ancho útil y `spaceBetween` los reparte de borde a borde.
        //
        // Antes el Row medía solo su contenido y quedaba apoyado contra el
        // margen izquierdo: en un iPhone de 393pt los pills terminaban a los
        // 321 y sobraban 72pt de aire muerto a la derecha. Ahora el primero
        // muere contra el margen izquierdo y el último contra el derecho,
        // igual que el toggle y el botón `+` de la fila de arriba.
        //
        // Los `SizedBox` de 12 quedan como separación MÍNIMA. Con
        // `spaceBetween` los cuatro huecos son iguales, así que las dos
        // separaciones visibles entre pills salen iguales igual: 12 + 2·hueco.
        final innerWidth = constraints.maxWidth - 2 * _kSideMargin;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: _kSideMargin),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: innerWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Pill(
                  label: l10n.feedSegmentFollowing,
                  isActive: segment == FeedSegment.amigos,
                  onTap: () => ref.read(feedSegmentProvider.notifier).state =
                      FeedSegment.amigos,
                ),
                const SizedBox(width: 12),
                _Pill(
                  label: 'MI GYM',
                  isActive: segment == FeedSegment.gym,
                  onTap: () => ref.read(feedSegmentProvider.notifier).state =
                      FeedSegment.gym,
                ),
                const SizedBox(width: 12),
                _Pill(
                  label: 'PÚBLICO',
                  isActive: segment == FeedSegment.public,
                  onTap: () => ref.read(feedSegmentProvider.notifier).state =
                      FeedSegment.public,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isActive ? palette.bg : palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
