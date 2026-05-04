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
                  AuthStrings.loginTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                AuthTextField(
                  controller: _emailCtrl,
                  label: AuthStrings.loginEmailLabel,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  focusNode: _emailFocus,
                  nextFocusNode: _passwordFocus,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _passwordCtrl,
                  label: AuthStrings.loginPasswordLabel,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  focusNode: _passwordFocus,
                  onFieldSubmitted: (_) => _fieldsEmpty ? null : _submit(),
                  autofillHints: const [AutofillHints.password],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/forgot-password'),
                    child: Text(
                      AuthStrings.loginForgot,
                      style: TextStyle(color: palette.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (failure != null) ...[
                  AuthFailureBanner(failure: failure),
                  const SizedBox(height: 12),
                ],
                AuthPrimaryButton(
                  label: AuthStrings.loginSubmit,
                  onPressed: _fieldsEmpty ? null : _submit,
                  isLoading: isLoading,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AuthStrings.loginNoAccount,
                      style: TextStyle(color: palette.textMuted),
                    ),
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: Text(
                        AuthStrings.loginRegisterLink,
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
