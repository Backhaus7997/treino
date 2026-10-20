import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Full-width pill CTA with loading state and glow shadow.
/// Replaces AuthPrimaryButton with mockup-aligned styling.
///
/// [outlined] es la versión invertida —fondo `bg`, borde y texto `accent`,
/// sin glow— para la acción secundaria que va debajo de la principal con el
/// mismo tamaño y forma (p. ej. INICIAR SESIÓN bajo EMPEZAR).
class AuthPillButton extends StatelessWidget {
  const AuthPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.showArrow = true,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool showArrow;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fill = outlined ? palette.bg : palette.accent;
    final ink = outlined ? palette.accent : palette.bg;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        boxShadow: [
          if (!outlined)
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: outlined
              ? palette.accent
              : TreinoButtonTokens.foreground(context),
          disabledBackgroundColor: fill.withValues(alpha: 0.5),
          shape: StadiumBorder(
            side: outlined
                ? BorderSide(color: palette.accent, width: 1.5)
                : BorderSide.none,
          ),
          elevation: outlined ? 0 : null,
          padding: EdgeInsets.zero,
        ),
        child: isLoading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    outlined
                        ? palette.accent
                        : TreinoButtonTokens.foreground(context),
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: ink,
                    ),
                  ),
                  if (showArrow) ...[
                    const SizedBox(width: 8),
                    Icon(
                      TreinoIcon.arrowRight,
                      size: 18,
                      color: ink,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
