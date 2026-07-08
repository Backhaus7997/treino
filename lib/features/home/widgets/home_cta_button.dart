import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';

/// Full-width pill CTA used on the Home screen.
/// Mirrors the visual style of [AuthPillButton] without the loading state —
/// no network call needed (navigation is synchronous, YAGNI for isLoading).
///
/// TREINO Motion PR3: [TreinoTappable] + `Container` reemplazan al
/// `ElevatedButton` — feedback de presión por scale (0.97) en lugar del
/// ripple de Material. Reemplazo limpio: un solo manejador de tap (envolver
/// el ElevatedButton habría metido dos recognizers compitiendo en el
/// gesture arena). El rol de botón para accesibilidad se preserva con
/// [Semantics] explícito, que el ElevatedButton aportaba implícitamente.
class HomeCTAButton extends StatelessWidget {
  const HomeCTAButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Optional leading icon. Accepts a [TreinoIcon] constant (type: [IconData]).
  /// When null no [Icon] widget is rendered inside the button.
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onPressed != null;
    // Mismos colores que tenía el ElevatedButton: accent pleno habilitado,
    // accent al 50% deshabilitado; el foreground era palette.bg en ambos.
    final bg = enabled ? palette.accent : palette.accent.withValues(alpha: 0.5);

    return Semantics(
      button: true,
      enabled: enabled,
      child: TreinoTappable(
        onTap: onPressed,
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: ShapeDecoration(
            color: bg,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, color: palette.bg, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  color: palette.bg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
