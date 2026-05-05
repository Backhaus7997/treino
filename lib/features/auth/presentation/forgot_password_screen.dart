import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
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
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // Headline
                Text(
                  AuthStrings.forgotTitle,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: palette.textPrimary,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                // Body
                Text(
                  AuthStrings.forgotBody,
                  style: GoogleFonts.barlow(
                    fontSize: 15,
                    color: palette.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                if (_sent) ...[
                  // Success state
                  Text(
                    AuthStrings.forgotSuccess,
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
                    label: AuthStrings.forgotEmailLabel,
                    hint: AuthStrings.forgotEmailHint,
                    leadingIcon: TreinoIcon.mail,
                    keyboardType: TextInputType.emailAddress,
                    enabled: false,
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      AuthStrings.forgotBackToLogin,
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ] else ...[
                  // Form state
                  AuthInput(
                    controller: _emailCtrl,
                    label: AuthStrings.forgotEmailLabel,
                    hint: AuthStrings.forgotEmailHint,
                    leadingIcon: TreinoIcon.mail,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    onFieldSubmitted: (_) =>
                        _emailCtrl.text.trim().isEmpty ? null : _submit(),
                  ),
                  const SizedBox(height: 20),
                  if (_failure != null) ...[
                    AuthFailureBanner(failure: _failure!),
                    const SizedBox(height: 12),
                  ],
                  AuthPillButton(
                    label: AuthStrings.forgotCta,
                    onPressed: _emailCtrl.text.trim().isEmpty ? null : _submit,
                    isLoading: _isLoading,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
