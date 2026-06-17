import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/auth_providers.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/auth_failure.dart';
import '../domain/email_password_validator.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/password_strength_bar.dart';
import 'widgets/terms_checkbox.dart';
import 'widgets/treino_logo.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() => setState(() {}));
    _passwordCtrl.addListener(() => setState(() {}));
    _confirmPasswordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  bool get _fieldsEmpty =>
      _emailCtrl.text.trim().isEmpty ||
      _passwordCtrl.text.isEmpty ||
      _confirmPasswordCtrl.text.isEmpty;

  bool get _canSubmit => !_fieldsEmpty && _termsAccepted;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // No displayName at signup — populated by ProfileSetup in Etapa 6 (REQ-AUTH-002).
    await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    final s = ref.read(authNotifierProvider);
    if (s.hasValue && s.valueOrNull != null) {
      context.go('/home');
    }
  }

  Future<void> _signInWithGoogle() async {
    // Terms must be accepted even when registering with Google — the OAuth
    // flow still creates a TREINO account. Surface a snackbar instead of
    // silently doing nothing so the user knows what is missing.
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aceptá los Términos y la Política de Privacidad para continuar',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final s = ref.read(authNotifierProvider);
    if (s.hasValue && s.valueOrNull != null) {
      context.go('/home');
    }
  }

  Future<void> _signInWithApple() async {
    // Same Terms gate as Google: Apple Sign-In also creates a TREINO account
    // on first sign-in, so the user must accept Terms first.
    if (!_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aceptá los Términos y la Política de Privacidad para continuar',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    await ref.read(authNotifierProvider.notifier).signInWithApple();
    if (!mounted) return;
    final s = ref.read(authNotifierProvider);
    if (s.hasValue && s.valueOrNull != null) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
    final failure = authState.hasError && authState.error is AuthFailure
        ? authState.error as AuthFailure
        : null;

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
                  // Back button — top left (same pattern as Login)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: l10n.commonBack,
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/welcome'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Headline: "SUMATE A" + TREINO brand logo below.
                  // Space Grotesk for the prose, brand SVG for the wordmark.
                  Text(
                    l10n.authRegisterTitle,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const TreinoLogo(size: 44),
                  const SizedBox(height: 14),
                  Text(
                    l10n.authRegisterSubtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 15,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Email field (no display name field — ProfileSetup owns it).
                  AuthInput(
                    controller: _emailCtrl,
                    label: l10n.authRegisterEmailLabel,
                    leadingIcon: TreinoIcon.mail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    focusNode: _emailFocus,
                    nextFocusNode: _passwordFocus,
                    autofillHints: const [AutofillHints.email],
                    validator: EmailPasswordValidator.validateEmail,
                  ),
                  const SizedBox(height: 14),
                  // Password field
                  AuthInput(
                    controller: _passwordCtrl,
                    label: l10n.authRegisterPasswordLabel,
                    leadingIcon: TreinoIcon.lock,
                    obscureText: true,
                    suffixToggle: true,
                    textInputAction: TextInputAction.next,
                    focusNode: _passwordFocus,
                    nextFocusNode: _confirmPasswordFocus,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: EmailPasswordValidator.validatePassword,
                  ),
                  const SizedBox(height: 4),
                  // Strength bar — pegada al input por diseño (single block)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _passwordCtrl,
                    builder: (_, value, __) =>
                        PasswordStrengthBar(password: value.text),
                  ),
                  const SizedBox(height: 14),
                  // Confirm password field
                  AuthInput(
                    controller: _confirmPasswordCtrl,
                    label: l10n.authRegisterConfirmPasswordLabel,
                    leadingIcon: TreinoIcon.lock,
                    obscureText: true,
                    suffixToggle: true,
                    textInputAction: TextInputAction.done,
                    focusNode: _confirmPasswordFocus,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: (value) =>
                        EmailPasswordValidator.validatePasswordMatch(
                      _passwordCtrl.text,
                      value,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Terms checkbox
                  TermsCheckbox(
                    value: _termsAccepted,
                    onChanged: (v) => setState(() => _termsAccepted = v),
                  ),
                  const SizedBox(height: 20),
                  // Error banner
                  if (failure != null) ...[
                    AuthFailureBanner(failure: failure),
                    const SizedBox(height: 12),
                  ],
                  // CTA
                  AuthPillButton(
                    label: l10n.authRegisterCta,
                    onPressed: _canSubmit ? _submit : null,
                    isLoading: isLoading,
                  ),
                  const SizedBox(height: 20),
                  // Divider "O"
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          l10n.authRegisterDividerOr,
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Social buttons. Google stays enabled regardless of the
                  // Terms checkbox so that tapping yields explicit feedback
                  // (snackbar) instead of looking like a "Próximamente"
                  // disabled control. The Terms requirement is enforced
                  // inside _signInWithGoogle.
                  Row(
                    children: [
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: FontAwesomeIcons.google,
                          iconWidget: SvgPicture.asset(
                            'assets/logo/google_g.svg',
                            width: 18,
                            height: 18,
                          ),
                          label: l10n.authGoogleLabel,
                          onPressed: isLoading ? null : _signInWithGoogle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: FontAwesomeIcons.apple,
                          label: l10n.authAppleLabel,
                          onPressed: isLoading ? null : _signInWithApple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
