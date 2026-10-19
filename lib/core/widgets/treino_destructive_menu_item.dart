import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';

/// Ítem de menú emergente para acciones destructivas (ELIMINAR, etc.).
///
/// Pinta el texto en `AppPalette.dangerText` (el color de peligro para TEXTO,
/// legible en las dos paletas). El resto del estilo —Barlow 600, tamaño—
/// lo pone `popupMenuTheme`. Un `Text` hijo sin estilo propio hereda el color;
/// para ícono + texto, pasar el mismo color al ícono.
class TreinoDestructiveMenuItem<T> extends PopupMenuItem<T> {
  TreinoDestructiveMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    super.padding,
    required Widget child,
  }) : super(
          child: Builder(
            builder: (context) => DefaultTextStyle.merge(
              style: TextStyle(color: AppPalette.of(context).dangerText),
              child: child,
            ),
          ),
        );
}
