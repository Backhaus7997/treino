import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';

/// Destructive confirmation bottom sheet for account deletion (Fase 6 Etapa 3).
///
/// Shows irreversible-action copy, CANCELAR + ELIMINAR buttons.
/// On ELIMINAR: calls [AccountDeletionNotifier.deleteAccount].
/// Loading overlay: shows "Eliminando tu cuenta..." during [AsyncLoading].
/// Error: shows SnackBar with "Reintentar" action.
class EliminarCuentaSheet extends ConsumerWidget {
  const EliminarCuentaSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final notifierState = ref.watch(accountDeletionNotifierProvider);

    ref.listen<AsyncValue<void>>(
      accountDeletionNotifierProvider,
      (previous, next) {
        next.whenOrNull(
          error: (e, _) {
            final message = e is AuthFailure
                ? e.userMessage
                : 'No pudimos eliminar tu cuenta. Probá de nuevo.'; // i18n: Fase 6 Etapa 3

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                action: SnackBarAction(
                  label: 'Reintentar', // i18n: Fase 6 Etapa 3
                  onPressed: () => ref
                      .read(accountDeletionNotifierProvider.notifier)
                      .retry(context),
                ),
              ),
            );
          },
        );
      },
    );

    final isLoading = notifierState.isLoading;

    return Stack(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                  'Eliminar cuenta', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.danger,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: palette.textMuted,
                    ),
                    children: const [
                      TextSpan(
                        // i18n: Fase 6 Etapa 3
                        text: 'Esta acción es ',
                      ),
                      TextSpan(
                        text: 'irreversible', // i18n: Fase 6 Etapa 3
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        // i18n: Fase 6 Etapa 3
                        text:
                            '. Vamos a eliminar tu cuenta, tu perfil, tu historial '
                            'de entrenamientos y tu foto. Tus posts van a quedar '
                            'como "Usuario eliminado".',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          ref
                              .read(accountDeletionNotifierProvider.notifier)
                              .deleteAccount(context);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'ELIMINAR', // i18n: Fase 6 Etapa 3
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: palette.bg,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.of(context).pop(),
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
        ),
        // Loading overlay
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: palette.bg.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: palette.accent),
                    const SizedBox(height: 18),
                    Text(
                      'Eliminando tu cuenta...', // i18n: Fase 6 Etapa 3
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esto puede tardar unos segundos.', // i18n: Fase 6 Etapa 3
                      style: TextStyle(
                        fontSize: 14,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
