import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Circular outlined back button used at the top-left of auth screens
/// (ForgotPassword, Login, Register). Matches the mockup style: thin border,
/// transparent fill, centered chevron.
class AuthCircleBackButton extends StatelessWidget {
  const AuthCircleBackButton({
    super.key,
    required this.onPressed,
    this.size = 44,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Material(
      color: Colors.transparent,
      shape: CircleBorder(
        side: BorderSide(color: palette.border, width: 1),
      ),
      child: Semantics(
        button: true,
        label: l10n.commonBack,
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
      ),
    );
  }
}
