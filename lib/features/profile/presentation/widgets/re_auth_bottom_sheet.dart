import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';

/// Provider-aware re-authentication bottom sheet (Fase 6 Etapa 3).
///
/// Per ADR-ACCDEL-008: ONE widget that branches at runtime on [providerId].
/// Private body widgets: [_PasswordReAuthBody], [_GoogleReAuthBody],
/// [_AppleReAuthBody]. Sheet pops with the resulting [AuthCredential?]:
///   - non-null → credential obtained, re-auth succeeded
///   - null     → user cancelled
class ReAuthBottomSheet extends ConsumerStatefulWidget {
  const ReAuthBottomSheet({super.key, required this.providerId});

  /// Provider ID detected from `user.providerData[0].providerId`.
  final String providerId;

  @override
  ConsumerState<ReAuthBottomSheet> createState() => _ReAuthBottomSheetState();
}

class _ReAuthBottomSheetState extends ConsumerState<ReAuthBottomSheet> {
  String? _errorMessage;

  void _setError(String msg) {
    if (mounted) setState(() => _errorMessage = msg);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Confirmá tu identidad', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              // i18n: Fase 6 Etapa 3
              'Por seguridad, necesitamos confirmar que sos vos antes de eliminar tu cuenta.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            // Branch per provider
            switch (widget.providerId) {
              'google.com' => _GoogleReAuthBody(
                  palette: palette,
                  onError: _setError,
                ),
              'apple.com' => _AppleReAuthBody(
                  palette: palette,
                  onError: _setError,
                ),
              _ => _PasswordReAuthBody(
                  palette: palette,
                  onError: _setError,
                ),
            },
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: palette.danger, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                'CANCELAR', // i18n: Fase 6 Etapa 3
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private body widgets ──────────────────────────────────────────────────────

class _PasswordReAuthBody extends ConsumerStatefulWidget {
  const _PasswordReAuthBody({
    required this.palette,
    required this.onError,
  });

  final AppPalette palette;
  final void Function(String) onError;

  @override
  ConsumerState<_PasswordReAuthBody> createState() =>
      _PasswordReAuthBodyState();
}

class _PasswordReAuthBodyState extends ConsumerState<_PasswordReAuthBody> {
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final credential =
          await authService.getPasswordCredential(password: password);
      await authService.reauthenticate(credential);
      if (mounted) Navigator.of(context).pop(credential);
    } on AuthFailure catch (e) {
      widget.onError(e.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _passwordController,
          obscureText: true,
          style: TextStyle(color: widget.palette.textPrimary),
          decoration: InputDecoration(
            labelText: 'Contraseña', // i18n: Fase 6 Etapa 3
            labelStyle: TextStyle(color: widget.palette.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: widget.palette.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: widget.palette.accent),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.palette.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.palette.bg,
                    ),
                  )
                : Text(
                    'CONTINUAR', // i18n: Fase 6 Etapa 3
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: widget.palette.bg,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _GoogleReAuthBody extends ConsumerStatefulWidget {
  const _GoogleReAuthBody({
    required this.palette,
    required this.onError,
  });

  final AppPalette palette;
  final void Function(String) onError;

  @override
  ConsumerState<_GoogleReAuthBody> createState() => _GoogleReAuthBodyState();
}

class _GoogleReAuthBodyState extends ConsumerState<_GoogleReAuthBody> {
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.getGoogleCredential();
      await authService.reauthenticate(credential);
      if (mounted) Navigator.of(context).pop(credential);
    } on AuthFailure catch (e) {
      // Swallow signInCancelled — user intentionally dismissed, not an error.
      // Swallow signInCancelled — user intentionally dismissed, not an error.
      if (e.whenOrNull(signInCancelled: () => true) != true) {
        widget.onError(e.userMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.palette.accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _loading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.palette.bg,
                ),
              )
            : Text(
                'Continuar con Google', // i18n: Fase 6 Etapa 3
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: widget.palette.bg,
                ),
              ),
      ),
    );
  }
}

class _AppleReAuthBody extends ConsumerStatefulWidget {
  const _AppleReAuthBody({
    required this.palette,
    required this.onError,
  });

  final AppPalette palette;
  final void Function(String) onError;

  @override
  ConsumerState<_AppleReAuthBody> createState() => _AppleReAuthBodyState();
}

class _AppleReAuthBodyState extends ConsumerState<_AppleReAuthBody> {
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final credential = await authService.getAppleCredential();
      await authService.reauthenticate(credential);
      if (mounted) Navigator.of(context).pop(credential);
    } on AuthFailure catch (e) {
      // Swallow signInCancelled — user intentionally dismissed, not an error.
      // Swallow signInCancelled — user intentionally dismissed, not an error.
      if (e.whenOrNull(signInCancelled: () => true) != true) {
        widget.onError(e.userMessage);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.palette.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _loading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.palette.bg,
                ),
              )
            : Text(
                'Continuar con Apple', // i18n: Fase 6 Etapa 3
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: widget.palette.bg,
                ),
              ),
      ),
    );
  }
}
