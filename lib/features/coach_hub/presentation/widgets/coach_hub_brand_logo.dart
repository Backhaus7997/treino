import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_logo.dart';

/// El wordmark oficial de TREINO para el chrome del Coach Hub, con el color
/// que le toca según el fondo del tema activo.
///
/// Envuelve a [TreinoLogo] —el mismo widget que usan welcome, splash, login y
/// register del móvil, sobre `assets/logo/treino_logo.svg`— y sólo resuelve las
/// dos cosas que ese widget deja abiertas, color y halo:
///
/// - **Fondo oscuro**: `accent` (mint) con su halo. Es el verde con el que la
///   marca aparece en el sidebar.
/// - **Fondo claro**: `textPrimary` (ink), sin halo. El mint pleno sobre el
///   fondo claro compone 1,57:1 (`AGENTS.md` §2), así que el wordmark se lee
///   apenas, y el manual de marca sobre claro manda negro o violeta, nunca el
///   verde. El halo también sobra: es mint desenfocado sobre casi blanco, y en
///   vez de brillar ensucia el contorno de las letras (se ve al rasterizar las
///   dos variantes lado a lado).
///
/// Se resuelve por tema y no con un color fijo porque el Coach Hub arranca en
/// `ThemeMode.system`: el mismo teléfono ve el encabezado, el login y la vista
/// de carga en claro u oscuro según el ajuste del sistema. Los tres usos tienen
/// que coincidir, y por eso la regla vive en un solo lugar.
///
/// La rama se decide con `Theme.of(context).brightness` y no con un token de
/// [AppPalette] a propósito: no existe un token de "tinta de marca", y crearlo
/// tocaría la paleta entera (constructor, `copyWith`, `lerp`) por un único
/// consumidor.
class CoachHubBrandLogo extends StatelessWidget {
  const CoachHubBrandLogo({super.key, required this.size});

  /// Alto del wordmark en px lógicos — el mismo contrato que
  /// [TreinoLogo.size]. El ancho sale de la proporción del SVG (~1,97:1).
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final onDark = Theme.of(context).brightness == Brightness.dark;

    // Antes la marca era el texto "TREINO", que un lector de pantalla leía.
    // El SVG no tiene texto, así que el nombre se lo damos nosotros.
    return Semantics(
      label: 'TREINO',
      image: true,
      excludeSemantics: true,
      child: TreinoLogo(
        size: size,
        color: onDark ? palette.accent : palette.textPrimary,
        glow: onDark,
      ),
    );
  }
}
