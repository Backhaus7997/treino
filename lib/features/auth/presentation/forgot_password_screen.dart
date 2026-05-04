import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import '../domain/auth_failure.dart';
import 'auth_strings.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  String _sentEmail = '';
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
        _sentEmail = email;
        _isLoading = false;
      });
    } on AuthFailure catch (f) {
      if (!mounted) return;
      // REQ-AUTH-011: userNotFound MUST be treated as success (security).
      if (f == const AuthFailure.userNotFound()) {
        setState(() {
          _sent = true;
          _sentEmail = email;
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                AuthStrings.forgotTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AuthStrings.forgotSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              if (_sent) ...[
                Text(
                  AuthStrings.forgotSuccess(_sentEmail),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 20),
                // Field shown as read-only after success
                AuthTextField(
                  controller: _emailCtrl,
                  label: AuthStrings.forgotEmailLabel,
                  keyboardType: TextInputType.emailAddress,
                  enabled: false,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text(
                    AuthStrings.forgotBackToLogin,
                    style: TextStyle(color: palette.accent),
                  ),
                ),
              ] else ...[
                AuthTextField(
                  controller: _emailCtrl,
                  label: AuthStrings.forgotEmailLabel,
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
                AuthPrimaryButton(
                  label: AuthStrings.forgotSubmit,
                  onPressed: _emailCtrl.text.trim().isEmpty ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: Text(
                    AuthStrings.forgotBackToLogin,
                    style: TextStyle(color: palette.accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
