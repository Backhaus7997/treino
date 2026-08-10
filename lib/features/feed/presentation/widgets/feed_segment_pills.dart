import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/feed_screen_providers.dart';
import '../../domain/feed_segment.dart';
import '../../../../l10n/app_l10n.dart';

/// Margen lateral de la fila de segmentos. Es el mismo 20 que usan el header
/// del feed y el resto del shell: los pills tienen que alinearse con ellos.
const double _kSideMargin = 20;

/// Separación entre pills. Fija, no repartida.
const double _kPillGap = 12;

class FeedSegmentPills extends ConsumerWidget {
  const FeedSegmentPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final segment = ref.watch(feedSegmentProvider);

    // Los tres pills se reparten el ancho en partes IGUALES.
    //
    // Antes medían lo que medía su texto y el Row quedaba apoyado contra el
    // margen izquierdo: en un iPhone de 393pt terminaban a los 321 y sobraban
    // 72pt de aire muerto a la derecha. El intento siguiente fue estirar el
    // Row y repartir el sobrante con `spaceBetween`, y quedó peor: la
    // separación entre pills saltaba de 12 a ~37 y se leían como tres cosas
    // sueltas en vez de un control.
    //
    // Partes iguales resuelve las dos cosas de una: la fila llega a los dos
    // márgenes —alineada con el toggle y el botón `+` de arriba— y la
    // separación se queda en los 12 del diseño. Además le da a los tres la
    // misma área tapeable, que con anchos naturales quedaba a merced de lo
    // largo que fuera cada palabra.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kSideMargin),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              label: l10n.feedSegmentFollowing,
              isActive: segment == FeedSegment.amigos,
              onTap: () => ref.read(feedSegmentProvider.notifier).state =
                  FeedSegment.amigos,
            ),
          ),
          const SizedBox(width: _kPillGap),
          Expanded(
            child: _Pill(
              label: 'MI GYM',
              isActive: segment == FeedSegment.gym,
              onTap: () => ref.read(feedSegmentProvider.notifier).state =
                  FeedSegment.gym,
            ),
          ),
          const SizedBox(width: _kPillGap),
          Expanded(
            child: _Pill(
              label: 'PÚBLICO',
              isActive: segment == FeedSegment.public,
              onTap: () => ref.read(feedSegmentProvider.notifier).state =
                  FeedSegment.public,
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        // El pill ya no se adapta al texto: mide lo que le toca de la fila.
        // Si el label no entra —pantalla muy angosta, textScale grande— se
        // achica en vez de desbordar. Es el mismo recurso que usa el toggle
        // FEED/RANKINGS del header, así que el gesto es consistente.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isActive ? palette.bg : palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
