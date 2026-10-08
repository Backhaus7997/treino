import 'package:flutter/material.dart';

import '../../app_palette.dart';
import '../primitives.dart';

/// Capa 3 — Tokens del PUNTO que marca una pestaña con contenido.
///
/// Vivían en `TreinoSegmentedPillTokens` porque la primera versión de las
/// marcas se implementó adentro de `TreinoSegmentedPill`. Cuando la navegación
/// de la ficha del alumno pasó a un `TabBar` con subrayado —el idioma del
/// Coach Hub web— la píldora dejó de tener nada que ver, y un token llamado
/// `TreinoSegmentedPillTokens.markSize` usado desde un `TabBar` era un nombre
/// que mentía sobre dónde vive la decisión.
///
/// La regla que estos tokens existen para fijar, y la única que puede romperse
/// en silencio: [attention] sale de `AppPalette.accentText` y **NO** de
/// `accent`. El mint pleno es un color de FONDO — como tinta compone 1,63:1
/// sobre una superficie clara, así que un punto de `accent` es invisible en
/// tema claro, que es el que se usa en el Coach Hub. El defecto **no se ve**
/// desde un test de pantalla: esos harness pumpean el tema oscuro, donde
/// `accent` y `accentText` son el mismo mint. Por eso el candado vive en
/// `treino_nav_mark_tokens_test.dart`, que mide las dos paletas.
@immutable
class TreinoNavMarkTokens {
  const TreinoNavMarkTokens._({
    required this.content,
    required this.attention,
  });

  /// Punto de «hay contenido adentro». Informa, no apura: es el mismo color
  /// que el label inactivo, así que se lee como parte de la etiqueta.
  final Color content;

  /// Punto de «esto reclama acción». Va en acento y por eso tiene que ser
  /// raro: si todo lleva acento, el acento deja de señalar algo.
  ///
  /// `accentText`, no `accent` — ver el dartdoc de la clase.
  final Color attention;

  /// Diámetro del punto — `AppSpacing.s8`.
  ///
  /// El valor más chico de la escala cerrada, que acá es el correcto: es una
  /// marca al lado de un label de 14, no un badge.
  static const double size = AppSpacing.s8;

  /// Separación entre el label y su punto — `AppSpacing.hairline` (4).
  /// Gutter interno de un componente, que es el caso que `hairline` cubre.
  static const double gap = AppSpacing.hairline;

  factory TreinoNavMarkTokens.of(BuildContext ctx) {
    final p = AppPalette.of(ctx);
    return TreinoNavMarkTokens._(
      content: p.textMuted,
      attention: p.accentText,
    );
  }

  /// Resuelve contra una paleta concreta, para poder medir las DOS sin montar
  /// un árbol de widgets por tema.
  factory TreinoNavMarkTokens.fromPalette(AppPalette p) =>
      TreinoNavMarkTokens._(content: p.textMuted, attention: p.accentText);
}
