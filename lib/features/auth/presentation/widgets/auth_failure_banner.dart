import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

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
      // #1505: era `errorContainer` de Material — rojo saturado, 3,6:1 con
      // el texto en los dos temas. Ahora el rojo es un TINTE con borde (el
      // patrón de los errores inline) y el texto va en `textPrimary`, que
      // sobre el tinte pasa AA de sobra.
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: palette.danger.withValues(alpha: 0.5)),
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
