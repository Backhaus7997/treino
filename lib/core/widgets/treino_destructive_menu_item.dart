import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';

/// Ítem de menú emergente para acciones destructivas (ELIMINAR, etc.).
///
/// Pinta el texto —y el [icon], si viene— en `AppPalette.dangerText` (el
/// color de peligro para TEXTO, legible en las dos paletas). El resto del
/// estilo —Barlow 600, tamaño— lo pone `popupMenuTheme.labelTextStyle`. Un
/// `Text` hijo sin estilo propio hereda el color.
///
/// Deshabilitado NO se pinta de peligro: queda en el estilo deshabilitado del
/// tema, igual que cualquier otro ítem. Un rojo a pleno se lee como accionable.
class TreinoDestructiveMenuItem<T> extends PopupMenuItem<T> {
  TreinoDestructiveMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    super.padding,
    IconData? icon,
    required Widget child,
  }) : super(
          child: Builder(
            builder: (context) {
              final color = enabled ? AppPalette.of(context).dangerText : null;
              final contenido = icon == null
                  ? child
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 12),
                        child,
                      ],
                    );
              if (color == null) return contenido;
              return DefaultTextStyle.merge(
                style: TextStyle(color: color),
                child: contenido,
              );
            },
          ),
        );
}
