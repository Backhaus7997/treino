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
import 'auth_strings.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_input.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_secondary_button.dart';
import 'widgets/trainer_inquiry_card.dart';
import 'widgets/treino_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() => setState(() {}));
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _fieldsEmpty =>
      _emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty;

  Future<void> _submit() async {
    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
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
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button — top left
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/welcome'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Logo centered
                  const Center(child: TreinoLogo(size: 56)),
                  const SizedBox(height: 20),
                  // Headline
                  Text(
                    AuthStrings.loginTitle,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: palette.textPrimary,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    AuthStrings.loginSubtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 15,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Email field — no label per mockup (icon-only)
                  AuthInput(
                    controller: _emailCtrl,
                    hint: AuthStrings.loginEmailHint,
                    leadingIcon: TreinoIcon.mail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    focusNode: _emailFocus,
                    nextFocusNode: _passwordFocus,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 14),
                  // Password field — no label per mockup (icon-only)
                  AuthInput(
                    controller: _passwordCtrl,
                    leadingIcon: TreinoIcon.lock,
                    obscureText: true,
                    suffixToggle: true,
                    textInputAction: TextInputAction.done,
                    focusNode: _passwordFocus,
                    onFieldSubmitted: (_) => _fieldsEmpty ? null : _submit(),
                    autofillHints: const [AutofillHints.password],
                  ),
                  // Forgot password — right aligned
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      child: Text(
                        AuthStrings.loginForgot,
                        style: GoogleFonts.barlow(
                          fontSize: 14,
                          color: palette.accent,
                        ),
                      ),
                    ),
                  ),
                  // Error banner
                  if (failure != null) ...[
                    AuthFailureBanner(failure: failure),
                    const SizedBox(height: 12),
                  ],
                  // CTA
                  AuthPillButton(
                    label: AuthStrings.loginCta,
                    onPressed: _fieldsEmpty ? null : _submit,
                    isLoading: isLoading,
                  ),
                  const SizedBox(height: 18),
                  // Divider "O CONTINUÁ CON"
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          AuthStrings.loginContinueWith,
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
                  // No account row
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${AuthStrings.loginNoAccount} ',
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            color: palette.textMuted,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/register'),
                          child: Text(
                            AuthStrings.loginRegisterLink,
                            style: GoogleFonts.barlow(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Trainer inquiry card
                  const TrainerInquiryCard(),
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
