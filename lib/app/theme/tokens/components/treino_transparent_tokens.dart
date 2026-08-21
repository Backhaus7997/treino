import 'package:flutter/material.dart';

import '../primitives.dart';

/// Capa 3 — Token de componente compartido para "transparente" invariante.
///
/// Expone `AppColorPrimitives.transparent` a widgets fuera de un componente
/// puntual del kit (ej. overrides de `Theme.copyWith` para quitar
/// divider/splash/highlight de un `ExpansionTile`/`TabBar`, o el fondo
/// inactivo de un pill de selección) sin que referencien la capa 1
/// directamente — mismo criterio que `TreinoChipTokens.transparentBorder`
/// (Finding H1), pero sin acoplarse a la semántica de "borde de chip".
///
/// No requiere [BuildContext]: el valor no varía dark/light.
abstract final class TreinoTransparentTokens {
  static const Color value = AppColorPrimitives.transparent;
}
