import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

/// Acciones de seguridad que ya existen en Auth, sin crear un segundo flujo.
class SeguridadTab extends ConsumerStatefulWidget {
  const SeguridadTab({super.key});

  @override
  ConsumerState<SeguridadTab> createState() => _SeguridadTabState();
}

class _SeguridadTabState extends ConsumerState<SeguridadTab> {
  bool _sending = false;

  Future<void> _sendReset() async {
    final email = ref.read(userProfileProvider).valueOrNull?.email.trim();
    if (_sending || email == null || email.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email: email);
      _toast('Te mandamos un enlace a $email.');
    } catch (_) {
      _toast('No pudimos enviar el enlace. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final email = ref.watch(userProfileProvider).valueOrNull?.email.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEGURIDAD',
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w700,
            letterSpacing: AppFonts.headingTracking,
            color: palette.textPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          'Administrá el acceso a tu cuenta.',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        Container(
          padding: const EdgeInsets.all(AppSpacing.s20),
          decoration: BoxDecoration(
            color: TreinoCardTokens.background(context),
            border: Border.all(color: TreinoCardTokens.border(context)),
            borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
            boxShadow: TreinoCardTokens.boxShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cambiar contraseña',
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontWeight: AppFonts.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.hairline),
                    Text(
                      'Te enviamos el flujo seguro que ya usa TREINO a '
                      '${email?.isNotEmpty == true ? email : 'tu email'}.',
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        color: palette.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s14),
              // El label ya dice «ENVIANDO…», así que `loading` taparía la
              // única información que el botón tiene mientras espera.
              TreinoButton(
                label: _sending ? 'ENVIANDO…' : 'ENVIAR ENLACE',
                variant: TreinoButtonVariant.secondary,
                onPressed:
                    email?.isNotEmpty == true && !_sending ? _sendReset : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
