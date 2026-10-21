import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

/// Menú contextual tokenizado para reemplazar `PopupMenuButton` crudo.
class TreinoPopupMenuButton<T> extends StatelessWidget {
  const TreinoPopupMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
    this.initialValue,
    this.padding = const EdgeInsets.all(AppSpacing.s8),
    this.iconSize,
    this.style,
  }) : assert(icon == null || child == null);

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final T? initialValue;
  final EdgeInsetsGeometry padding;

  /// Tamaño del ícono. En null usa el default de `PopupMenuButton`, que es
  /// **24**: al lado de una fila de íconos de 18 el ⋮ mide de más.
  final double? iconSize;

  /// Estilo del `IconButton` interno.
  ///
  /// Es la ÚNICA forma de controlar su caja. `PopupMenuButton` le reenvía
  /// `padding`, `iconSize` y `style`, pero **no `constraints`** — ese
  /// parámetro suyo es para el MENÚ, no para el botón (ver `popup_menu.dart`,
  /// donde arma el `IconButton`). Quien necesite que el ⋮ mida igual que sus
  /// hermanos de un `Row` pasa un `IconButton.styleFrom(...)` con
  /// `minimumSize`, `padding` y `tapTargetSize`.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    // El look del menú (superficie, borde, radio, Barlow 600) lo pone
    // `popupMenuTheme` en `AppTheme` (#1558): acá no se pisa nada.
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: initialValue,
      padding: padding,
      iconSize: iconSize,
      style: style,
      icon: icon,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      child: child,
    );
  }
}
