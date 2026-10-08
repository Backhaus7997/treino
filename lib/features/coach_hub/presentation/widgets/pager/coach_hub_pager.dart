import 'package:flutter/material.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../treino_interactive_state.dart';

/// Filas por página en todas las listas del Coach Hub.
///
/// Sale de un pedido del PF —«que cualquier lista que haya no sea más grande
/// de 25 y que a partir de eso tenga que haber una segunda página para ver los
/// más viejos»— y es un número, no un cálculo: 25 filas entran en una pantalla
/// de escritorio sin que la página se vuelva un scroll infinito, y es un corte
/// que el PF puede predecir.
const int kCoachHubPageSize = 25;

/// Recorta [items] a la página [page] (0-based) de [pageSize] elementos.
///
/// Puro: sin `BuildContext`, sin estado, testeable solo. La UI decide qué
/// página mostrar; esto sólo corta.
///
/// [page] se **clampea**, no se valida. Un índice fuera de rango es una
/// situación normal, no un error del llamador: pasa cada vez que la lista se
/// achica debajo de la página que estás mirando —marcás el último pago
/// pendiente y el bucket queda en 3 filas mientras estás parado en la página
/// 2—. Tirar ahí sería convertir un evento cotidiano en un crash; devolver
/// vacío sería peor todavía, porque una lista vacía se lee como «no hay
/// nada» y acá el dato existe: sólo está en otra página. Se devuelve la última
/// página con contenido.
List<T> pageOf<T>(
  List<T> items, {
  required int page,
  int pageSize = kCoachHubPageSize,
}) {
  assert(pageSize > 0, 'pageSize tiene que ser positivo');
  if (items.isEmpty) return const [];
  final ultima = pageCount(items.length, pageSize: pageSize) - 1;
  final p = page.clamp(0, ultima);
  final desde = p * pageSize;
  return items.sublist(desde, (desde + pageSize).clamp(0, items.length));
}

/// Cantidad de páginas para [total] elementos. Nunca menos de 1: una lista
/// vacía sigue siendo «página 1 de 1», que es lo que el pie tiene que decir
/// para no quedar en «1 de 0».
int pageCount(int total, {int pageSize = kCoachHubPageSize}) {
  assert(pageSize > 0, 'pageSize tiene que ser positivo');
  if (total <= 0) return 1;
  return (total + pageSize - 1) ~/ pageSize;
}

/// Pie de paginado del Coach Hub: «26–50 de 112» con anterior / siguiente.
///
/// **Se oculta solo cuando hay una sola página.** Un paginador de una página
/// es ruido que además miente sobre el tamaño de la lista, y la mayoría de las
/// listas del Coach Hub viven abajo de 25 filas durante mucho tiempo.
class CoachHubPager extends StatelessWidget {
  const CoachHubPager({
    super.key,
    required this.total,
    required this.page,
    required this.onPageChanged,
    this.pageSize = kCoachHubPageSize,
  });

  /// Total de elementos ANTES de recortar — el `112` de «26–50 de 112».
  final int total;

  /// Página actual, 0-based.
  final int page;

  final ValueChanged<int> onPageChanged;
  final int pageSize;

  @override
  Widget build(BuildContext context) {
    final paginas = pageCount(total, pageSize: pageSize);
    if (paginas <= 1) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final p = page.clamp(0, paginas - 1);
    final desde = p * pageSize + 1;
    final hasta = ((p + 1) * pageSize).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$desde–$hasta de $total', // i18n
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontSize: AppTextSize.caption,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          _PagerButton(
            key: const Key('coach_hub_pager_prev'),
            icon: TreinoIcon.chevronLeft,
            tooltip: 'Página anterior', // i18n
            // `null` y no un callback que no hace nada: un botón que se ve
            // igual y no responde manda al PF a tocarlo dos veces buscando el
            // error. Deshabilitado se ve deshabilitado.
            onTap: p == 0 ? null : () => onPageChanged(p - 1),
          ),
          const SizedBox(width: AppSpacing.hairline),
          _PagerButton(
            key: const Key('coach_hub_pager_next'),
            icon: TreinoIcon.chevronRight,
            tooltip: 'Página siguiente', // i18n
            onTap: p >= paginas - 1 ? null : () => onPageChanged(p + 1),
          ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final habilitado = onTap != null;
    return TreinoInteractiveState(
      onTap: onTap,
      builder: (context, state) => Tooltip(
        message: tooltip,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: state.hovered && habilitado
                ? palette.bgCard
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: palette.border),
          ),
          child: Icon(
            icon,
            size: 16,
            // El deshabilitado se apaga a la mitad en vez de cambiar de
            // token: `textMuted` sobre `bg` ya es el escalón más bajo de la
            // paleta, así que no hay un "más apagado" al que ir.
            color: palette.textMuted.withValues(alpha: habilitado ? 1 : 0.35),
          ),
        ),
      ),
    );
  }
}
