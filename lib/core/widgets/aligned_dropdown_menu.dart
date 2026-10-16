import 'package:flutter/material.dart';

/// Hace que el menú de un `DropdownButtonFormField` tenga el ancho y la
/// posición del CAMPO que lo abre (#1491).
///
/// Por default Flutter infla el rectángulo del botón 16 px a la izquierda y
/// 24 a la derecha (`_kUnalignedMenuMargin` en `dropdown.dart`) para armar el
/// menú. Dentro de un sheet con 20 px de padding, el campo mide
/// `ancho de pantalla − 40` y el menú le suma 40 más: termina tocando los dos
/// bordes de la pantalla, sin margen y corrido respecto del campo (medido en
/// un test: campo 20→370, menú 0→390 sobre 390 px).
///
/// `alignedDropdown` pone ese margen en cero, y el menú queda exactamente
/// debajo del campo. Es el mecanismo que Flutter ofrece para esto; ningún
/// parámetro del propio dropdown lo cambia.
class AlignedDropdownMenu extends StatelessWidget {
  const AlignedDropdownMenu({super.key, required this.child});

  /// El `DropdownButton` / `DropdownButtonFormField` a alinear.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ButtonTheme(alignedDropdown: true, child: child);
  }
}
