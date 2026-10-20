import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import 'auth_secondary_button.dart';

/// Proveedor social cuyo OAuth está en curso (ver [AuthSocialButtons.pending]).
enum AuthSocialProvider { google, apple }

/// «Continuar con Google» y «Continuar con Apple» a ancho completo, uno sobre
/// el otro (Login y Registro). La leyenda legal (`TermsNoticeText`) la pone la
/// pantalla justo debajo: acá sólo viven los botones.
class AuthSocialButtons extends StatelessWidget {
  const AuthSocialButtons({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.pending,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onApple;

  /// El botón de este proveedor cambia su logo por un spinner mientras dura
  /// el ida y vuelta del OAuth: sin eso la pantalla queda quieta, sin
  /// feedback, durante segundos. Null = ninguno en curso.
  final AuthSocialProvider? pending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    Widget spinner() => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(palette.textPrimary),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthSecondaryButton(
          icon: FontAwesomeIcons.google,
          iconWidget: pending == AuthSocialProvider.google
              ? spinner()
              : SvgPicture.asset(
                  'assets/logo/google_g.svg',
                  width: 18,
                  height: 18,
                ),
          label: l10n.authContinueWithGoogle,
          onPressed: onGoogle,
        ),
        const SizedBox(height: 12),
        AuthSecondaryButton(
          icon: FontAwesomeIcons.apple,
          iconWidget: pending == AuthSocialProvider.apple ? spinner() : null,
          label: l10n.authContinueWithApple,
          onPressed: onApple,
        ),
      ],
    );
  }
}
