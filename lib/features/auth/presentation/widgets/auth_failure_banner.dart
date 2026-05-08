import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/auth_failure.dart';

class AuthFailureBanner extends StatelessWidget {
  const AuthFailureBanner({super.key, required this.failure});

  final AuthFailure failure;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        failure.userMessage,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textPrimary,
            ),
      ),
    );
  }
}
