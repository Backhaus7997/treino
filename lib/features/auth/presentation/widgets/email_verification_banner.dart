import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/auth_providers.dart';
import '../auth_strings.dart';

class EmailVerificationBanner extends ConsumerStatefulWidget {
  const EmailVerificationBanner({super.key});

  @override
  ConsumerState<EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState
    extends ConsumerState<EmailVerificationBanner> {
  // Local session dismiss state (REQ-AUTH-014) — not persisted.
  bool _dismissed = false;
  bool _resending = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    await ref.read(authNotifierProvider.notifier).sendEmailVerification();
    if (!mounted) return;
    setState(() => _resending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final authState = ref.watch(authNotifierProvider);
    final user = authState.valueOrNull;

    // Hidden when verified or no user (REQ-AUTH-015).
    if (user == null || user.emailVerified) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AuthStrings.verifyBannerTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Dismiss button (REQ-AUTH-014)
              TextButton(
                onPressed: () => setState(() => _dismissed = true),
                child: Text(
                  AuthStrings.verifyDismiss,
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            ],
          ),
          Text(
            AuthStrings.verifyBannerSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          // Resend button (REQ-AUTH-013)
          _resending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _resend,
                  child: Text(
                    AuthStrings.verifyResend,
                    style: TextStyle(color: palette.accent),
                  ),
                ),
        ],
      ),
    );
  }
}
