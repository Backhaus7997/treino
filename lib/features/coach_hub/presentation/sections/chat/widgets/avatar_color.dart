import 'package:flutter/material.dart';

/// Paleta de colores de avatar para el chat (mockup docs/web-trainer/screens/
/// chat/chat.png — círculos violeta/amarillo/rojo/verde/etc con la inicial).
///
/// Se elige de forma DETERMINÍSTICA a partir del uid, así el mismo alumno
/// siempre tiene el mismo color (no salta entre renders). Tonos saturados
/// que contrastan sobre fondos oscuros y con la inicial en blanco.
const List<Color> _kAvatarPalette = [
  Color(0xFF8B5CF6), // violeta
  Color(0xFFF59E0B), // ámbar
  Color(0xFFEF4444), // rojo
  Color(0xFF10B981), // verde
  Color(0xFF3B82F6), // azul
  Color(0xFFEC4899), // rosa
  Color(0xFF14B8A6), // teal
  Color(0xFFF97316), // naranja
];

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
