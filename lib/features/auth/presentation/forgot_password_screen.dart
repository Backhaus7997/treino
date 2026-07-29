import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/auth_providers.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/auth_failure.dart';
import '../domain/email_password_validator.dart';
import 'widgets/auth_circle_back_button.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sent = false;
  AuthFailure? _failure;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Catch malformed emails before the network call (align with register).
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim();
    setState(() {
      _isLoading = true;
      _failure = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .sendPasswordResetEmail(email: email);
      if (!mounted) return;
      // Success or userNotFound both treated as success (REQ-AUTH-011).
      setState(() {
        _sent = true;
        _isLoading = false;
      });
    } on AuthFailure catch (f) {
      if (!mounted) return;
      // REQ-AUTH-011: userNotFound MUST be treated as success (security).
      if (f == const AuthFailure.userNotFound()) {
        setState(() {
          _sent = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _failure = f;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      // Never swallow a user-initiated error silently: surface a generic
      // failure so AuthFailureBanner renders (Nielsen #1 visibility of system
      // status, #9 help users recover from errors).
      setState(() {
        _failure = const AuthFailure.unknown('reset-failed');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  AuthCircleBackButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/login'),
                  ),
                  const SizedBox(height: 24),
                  // Headline + body — entrada fade-slide sutil.
                  TreinoFadeSlideIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.authForgotTitle,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: palette.textPrimary,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.authForgotBody,
                          style: GoogleFonts.barlow(
                            fontSize: 15,
                            color: palette.textMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Cross-fade entre el form y el mensaje de éxito — momento
                  // de éxito claro sin competir con ninguna navegación (esta
                  // pantalla no redirige sola, el usuario vuelve a /login él
                  // mismo desde el link de abajo).
                  // Completa el patrón de login/register/welcome: el bloque
                  // de contenido entra con stagger(1) después del headline.
                  // TreinoStateSwitcher es un AnimatedSwitcher — NO anima su
                  // child inicial, así que sin este wrapper el form aparecía
                  // estático mientras el headline sí animaba.
                  TreinoFadeSlideIn(
                    delay: AppMotion.stagger(1),
                    child: TreinoStateSwitcher(
                      childKey: ValueKey(_sent),
                      child: _sent
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Success state
                                Text(
                                  l10n.authForgotSuccess,
                                  style: GoogleFonts.barlow(
                                    fontSize: 15,
                                    color: palette.accent,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Field shown as read-only after success
                                AuthInput(
                                  controller: _emailCtrl,
                                  label: l10n.authForgotEmailLabel,
                                  hint: l10n.authForgotEmailHint,
                                  leadingIcon: TreinoIcon.mail,
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: false,
                                ),
                                const SizedBox(height: 20),
                                TextButton(
                                  onPressed: () => context.go('/login'),
                                  child: Text(
                                    l10n.authForgotBackToLogin,
                                    style: GoogleFonts.barlow(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: palette.accent,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Form state
                                AuthInput(
                                  controller: _emailCtrl,
                                  label: l10n.authForgotEmailLabel,
                                  hint: l10n.authForgotEmailHint,
                                  leadingIcon: TreinoIcon.mail,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.email],
                                  validator:
                                      EmailPasswordValidator.validateEmail,
                                  onFieldSubmitted: (_) =>
                                      _emailCtrl.text.trim().isEmpty
                                          ? null
                                          : _submit(),
                                ),
                                const SizedBox(height: 20),
                                if (_failure != null) ...[
                                  AuthFailureBanner(failure: _failure!),
                                  const SizedBox(height: 12),
                                ],
                                AuthPillButton(
                                  label: l10n.authForgotCta,
                                  onPressed: _emailCtrl.text.trim().isEmpty
                                      ? null
                                      : _submit,
                                  isLoading: _isLoading,
                                  showArrow: false,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
