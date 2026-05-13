import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Circular outlined back button used at the top-left of auth screens
/// (ForgotPassword, Login, Register). Matches the mockup style: thin border,
/// transparent fill, centered chevron.
class AuthCircleBackButton extends StatelessWidget {
  const AuthCircleBackButton({
    super.key,
    required this.onPressed,
    this.size = 40,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Material(
      color: Colors.transparent,
      shape: CircleBorder(
        side: BorderSide(color: palette.border, width: 1),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            TreinoIcon.back,
            color: palette.textPrimary,
            size: 18,
          ),
        ),
      ),
    );
  }
}
