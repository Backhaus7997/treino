import 'package:flutter/material.dart';

import '../../../../../../app/theme/tokens/primitives.dart';

/// Paleta de colores de avatar para el chat (mockup docs/web-trainer/screens/
/// chat/chat.png — círculos violeta/amarillo/rojo/verde/etc con la inicial).
///
/// Se elige de forma DETERMINÍSTICA a partir del uid, así el mismo alumno
/// siempre tiene el mismo color (no salta entre renders). Tonos saturados
/// que contrastan sobre fondos oscuros y con la inicial en blanco.
///
/// Los valores viven en [AppDecorativePalettes.avatar]: `no_hex_scan_test`
/// admite hex literal sólo en `primitives.dart`. El orden de esa lista es
/// significativo — cambiarlo le cambia el color a todos los usuarios.
const List<Color> _kAvatarPalette = AppDecorativePalettes.avatar;

/// Color estable de avatar para [seed] (típicamente el uid del otro user).
/// Un [seed] vacío cae en el primer color de la paleta.
Color avatarColorFor(String seed) {
  if (seed.isEmpty) return _kAvatarPalette.first;
  // Hash simple y estable (no depende del hashCode de Dart, que varía entre
  // ejecuciones para strings).
  var hash = 0;
  for (final codeUnit in seed.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return _kAvatarPalette[hash % _kAvatarPalette.length];
}
