import 'package:flutter/material.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';

/// Avatar del kit Coach Hub Web con tinte derivado del nombre — reemplaza el
/// círculo apagado (fondo neutro + inicial gris) del diseño anterior.
///
/// Paleta ACOTADA de 3 tintes construidos desde [AppPalette] (mint/magenta/
/// sage, sin hex nuevos): el mismo [displayName] siempre resuelve al mismo
/// tinte (hash determinístico), así un alumno mantiene su color en cualquier
/// pantalla que lo muestre (chat, rutinas, ...).
///
/// Introducido en la ronda de revisión de Chat (list pane + detail header,
/// `ADR` implícito: "reusar > copiar") y promovido a este kit compartido para
/// que Rutinas lo consuma sin duplicar la lógica de tinte.
class TreinoAvatar extends StatelessWidget {
  const TreinoAvatar({
    super.key,
    required this.displayName,
    required this.avatarUrl,
    this.diameter = 44,
    this.initialFontSize = 16,
  });

  /// `null` = perfil todavía resolviendo (loading) — círculo neutro sin
  /// texto, evita el parpadeo de un tinte/inicial que después cambia.
  /// No-null (incluso `'?'` o `'Usuario eliminado'`) = ya resuelto.
  final String? displayName;

  final String? avatarUrl;
  final double diameter;
  final double initialFontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = displayName;

    if (name == null) {
      return CircleAvatar(
        radius: diameter / 2,
        backgroundColor: palette.bgCard,
      );
    }

    final tint = _TreinoAvatarTint.of(context, name);
    final hasImage = avatarUrl != null && avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: tint.background,
      backgroundImage: hasImage ? NetworkImage(avatarUrl!) : null,
      child: hasImage
          ? null
          : Text(
              _initial(name),
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: initialFontSize,
                color: tint.foreground,
              ),
            ),
    );
  }
}

String _initial(String name) => name.isNotEmpty ? name[0].toUpperCase() : '?';

/// Tinte resuelto (fondo con alpha + texto sólido) para un [TreinoAvatar].
@immutable
class _TreinoAvatarTint {
  const _TreinoAvatarTint._({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;

  /// Resuelve un tinte determinístico entre 3 tonos de marca — mint/magenta/
  /// sage — a partir de la suma de code units de [seed]. Mismo nombre, mismo
  /// tinte, siempre; sin diccionario ni estado, solo aritmética sobre
  /// [AppPalette].
  static _TreinoAvatarTint of(BuildContext context, String seed) {
    final palette = AppPalette.of(context);
    final tones = [palette.accent, palette.highlight, palette.sage];
    final sum = seed.codeUnits.fold<int>(0, (acc, unit) => acc + unit);
    final tone = tones[sum % tones.length];
    return _TreinoAvatarTint._(
      // 20% de opacidad: visible sobre bgCard en ambos temas sin competir
      // con el texto del row.
      background: tone.withValues(alpha: 0.20),
      foreground: tone,
    );
  }
}
