import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../application/auth_providers.dart';
import '../domain/auth_failure.dart';
import '../domain/email_password_validator.dart';
import 'auth_strings.dart';
import 'widgets/auth_failure_banner.dart';
import 'widgets/auth_primary_button.dart';
import 'widgets/auth_text_field.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool get _fieldsEmpty =>
      _emailCtrl.text.trim().isEmpty ||
      _passwordCtrl.text.isEmpty ||
      _confirmCtrl.text.isEmpty;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    final state = ref.read(authNotifierProvider);
    if (state.hasValue && state.valueOrNull != null) {
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Form(
            key: _formKey,
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  AuthStrings.registerTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                AuthTextField(
                  controller: _emailCtrl,
                  label: AuthStrings.registerEmailLabel,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  focusNode: _emailFocus,
                  nextFocusNode: _passwordFocus,
                  autofillHints: const [AutofillHints.email],
                  validator: EmailPasswordValidator.validateEmail,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _passwordCtrl,
                  label: AuthStrings.registerPasswordLabel,
                  isPassword: true,
                  textInputAction: TextInputAction.next,
                  focusNode: _passwordFocus,
                  nextFocusNode: _confirmFocus,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: EmailPasswordValidator.validatePassword,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _confirmCtrl,
                  label: AuthStrings.registerConfirmLabel,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  focusNode: _confirmFocus,
                  onFieldSubmitted: (_) => _fieldsEmpty ? null : _submit(),
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) =>
                      EmailPasswordValidator.validatePasswordMatch(
                    _passwordCtrl.text,
                    v,
                  ),
                ),
                const SizedBox(height: 20),
                if (failure != null) ...[
                  AuthFailureBanner(failure: failure),
                  const SizedBox(height: 12),
                ],
                AuthPrimaryButton(
                  label: AuthStrings.registerSubmit,
                  onPressed: _fieldsEmpty ? null : _submit,
                  isLoading: isLoading,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AuthStrings.registerHasAccount,
                      style: TextStyle(color: palette.textMuted),
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: Text(
                        AuthStrings.registerLoginLink,
                        style: TextStyle(color: palette.accent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
