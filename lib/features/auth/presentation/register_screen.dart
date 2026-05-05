import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/auth_providers.dart';
import '../domain/auth_failure.dart';
import '../domain/email_password_validator.dart';
import 'auth_strings.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/password_strength_bar.dart';
import 'widgets/terms_checkbox.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _emailCtrl.addListener(() => setState(() {}));
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _fieldsEmpty =>
      _nameCtrl.text.trim().isEmpty ||
      _emailCtrl.text.trim().isEmpty ||
      _passwordCtrl.text.isEmpty;

  bool get _canSubmit => !_fieldsEmpty && _termsAccepted;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          displayName: _nameCtrl.text.trim(),
        );
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

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/welcome'),
        ),
        title: Text(
          AuthStrings.registerAppbar,
          style: GoogleFonts.barlowCondensed(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  // Headline
                  Text(
                    AuthStrings.registerTitle,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: palette.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AuthStrings.registerSubtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 15,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Name field
                  AuthInput(
                    controller: _nameCtrl,
                    label: AuthStrings.registerNameLabel,
                    hint: AuthStrings.registerNameHint,
                    leadingIcon: TreinoIcon.tabProfile,
                    textInputAction: TextInputAction.next,
                    focusNode: _nameFocus,
                    nextFocusNode: _emailFocus,
                  ),
                  const SizedBox(height: 14),
                  // Email field
                  AuthInput(
                    controller: _emailCtrl,
                    label: AuthStrings.registerEmailLabel,
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
                    label: AuthStrings.registerPasswordLabel,
                    leadingIcon: TreinoIcon.lock,
                    obscureText: true,
                    suffixToggle: true,
                    textInputAction: TextInputAction.done,
                    focusNode: _passwordFocus,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: EmailPasswordValidator.validatePassword,
                  ),
                  const SizedBox(height: 8),
                  // Strength bar — listens to password controller value
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _passwordCtrl,
                    builder: (_, value, __) =>
                        PasswordStrengthBar(password: value.text),
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
                    label: AuthStrings.registerCta,
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
                          AuthStrings.registerDividerOr,
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
                  // Social buttons
                  const Row(
                    children: [
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: FontAwesomeIcons.google,
                          label: AuthStrings.googleLabel,
                          onPressed: null,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: AuthSecondaryButton(
                          icon: FontAwesomeIcons.apple,
                          label: AuthStrings.appleLabel,
                          onPressed: null,
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
