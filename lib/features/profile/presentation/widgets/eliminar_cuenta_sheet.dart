import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/trainer_unlink_impact_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Destructive confirmation bottom sheet for account deletion (Fase 6 Etapa 3).
///
/// Shows irreversible-action copy, CANCELAR + ELIMINAR buttons.
/// On ELIMINAR: calls [AccountDeletionNotifier.deleteAccount].
/// Loading overlay: shows "Eliminando tu cuenta..." during [AsyncLoading].
/// Error: shows the message INSIDE the sheet with a "Reintentar" action.
class EliminarCuentaSheet extends ConsumerWidget {
  const EliminarCuentaSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final notifierState = ref.watch(accountDeletionNotifierProvider);

    // On confirmed account deletion (notifier flips this flag after the
    // CF reports the Auth user was deleted), force-navigate to /welcome.
    // The router's redirect would normally handle this when authStateChanges
    // emits null, but the CF deletes the Firestore user_profile BEFORE the
    // Auth user, which creates a brief window where loggedIn=true +
    // profile=null and the redirect lands on /profile-setup instead.
    // Forcing /welcome here makes the destination deterministic.
    ref.listen<bool>(
      accountDeletedFlagProvider,
      (previous, next) {
        if (next != true) return;

        // CERRAR EL SHEET A MANO. `context.go()` NO se lo lleva.
        //
        // El comentario de abajo daba por hecho que la redirección del router
        // desmontaba este modal «naturalmente». No: `go()` reemplaza el stack
        // de PÁGINAS de GoRouter, y un `showModalBottomSheet` vive como ruta
        // del Navigator RAÍZ, por encima de todo eso. La cuenta se borraba
        // bien, la app navegaba a /welcome, y el sheet quedaba flotando arriba
        // —con su título «Eliminar cuenta» y su botón ELIMINAR— sobre la
        // pantalla de bienvenida de una cuenta que ya no existe.
        //
        // `Navigator.of(context)` PELADO, sin `rootNavigator: true`.
        //
        // El sheet se abre desde `profile_screen`, que vive adentro del
        // `ShellRoute`, así que `showModalBottomSheet` lo empuja al navigator
        // del SHELL — no al raíz (lo documenta `router.dart` en el dartdoc de
        // `_shellNavigatorKey`). Pedir el raíz desde acá popea el navigator
        // equivocado. Sin argumento, resuelve el navigator que es dueño de
        // esta ruta, que es exactamente lo que ya hace CANCELAR unas líneas
        // más abajo y funciona.
        //
        // El router se captura ANTES del pop: después, el `context` de esta
        // ruta ya está desmontado y `context.go` sobre él revienta.
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go('/welcome');
      },
    );

    // El error NO va en un SnackBar: este sheet se abre en el Navigator RAÍZ
    // (`useRootNavigator: true`) y un SnackBar cuelga del Scaffold de la página
    // de abajo, o sea que el modal lo tapa y el usuario no ve por qué no se
    // borró su cuenta. El mensaje vive acá adentro, con su "Reintentar".
    final failure = notifierState.hasError ? notifierState.error : null;

    // Sólo el PF ve cuántos alumnos se desvinculan. `hasValue` y no
    // `valueOrNull`: sin conteo cargado no se afirma ninguno, y la baja nunca
    // espera a este valor.
    final isTrainer = ref.watch(
      userProfileProvider.select(
        (a) => a.valueOrNull?.role == UserRole.trainer,
      ),
    );
    final impact = isTrainer ? ref.watch(trainerUnlinkImpactProvider) : null;
    final unlinkCount =
        (impact != null && impact.hasValue) ? impact.requireValue : 0;

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
                  AppL10n.of(context).eliminarCuentaSheetTitle,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.danger,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final l10n = AppL10n.of(context);
                    return RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.barlow(
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                        children: [
                          TextSpan(text: l10n.eliminarCuentaSheetBodyPrefix),
                          TextSpan(
                            text: l10n.eliminarCuentaSheetBodyBold,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: l10n.eliminarCuentaSheetBodySuffix),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Eliminar la cuenta da de baja la suscripcion, pero NO devuelve
                // plata: el arrepentimiento es otro derecho y no lo ejerce esto.
                // Sin este aviso, quien borra la cuenta cree que se le reembolsa.
                Text(
                  AppL10n.of(context).eliminarCuentaSheetSubscriptionNote,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
                if (unlinkCount > 0) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    AppL10n.of(context)
                        .eliminarCuentaSheetTrainerUnlinkNotice(unlinkCount),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
                if (failure != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _errorMessage(AppL10n.of(context), failure),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: palette.danger,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(accountDeletionNotifierProvider.notifier)
                            .retry(context),
                    child: Text(
                      AppL10n.of(context).eliminarCuentaSheetRetryLabel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: palette.accentText,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  // Do NOT pop the sheet here — the notifier's flow needs
                  // a mounted listener for the loading overlay and the
                  // error snackbar to be visible. The success path pops the
                  // sheet via the `ref.listen` above.
                  onPressed: isLoading
                      ? null
                      : () => ref
                          .read(accountDeletionNotifierProvider.notifier)
                          .deleteAccount(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    AppL10n.of(context).eliminarCuentaSheetDeleteCta,
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
                    AppL10n.of(context).eliminarCuentaSheetCancelCta,
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
                      AppL10n.of(context).eliminarCuentaSheetLoadingLabel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppL10n.of(context).eliminarCuentaSheetLoadingSubtitle,
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

/// Mensaje del error de borrado. Las dos fallas que el servidor distingue
/// (`unavailable` y `permission-denied`) van por l10n; el resto conserva el
/// `userMessage` del dominio (es-AR, ADR-I18N-002).
String _errorMessage(AppL10n l10n, Object failure) {
  if (failure == const AuthFailure.subscriptionCancelFailed()) {
    return l10n.eliminarCuentaSheetErrorSubscriptionCancel;
  }
  if (failure == const AuthFailure.deletionNotAllowed()) {
    return l10n.eliminarCuentaSheetErrorNotAllowed;
  }
  return failure is AuthFailure
      ? failure.userMessage
      : l10n.eliminarCuentaSheetErrorFallback;
}
