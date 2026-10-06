import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/application/trainer_unlink_impact_provider.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Overrides que montan la baja de cuenta en la web (se agregan al
/// `ProviderScope` de `main_coach_hub.dart`).
///
/// El [AccountDeletionNotifier] es el mismo que usa mobile, con dos costuras
/// distintas porque ahí `GoogleSignIn` no existe:
/// - re-autenticación por popup / contraseña ([coachHubReauth]);
/// - cierre de sesión directo contra `FirebaseAuth`: `AuthService.signOut()`
///   espera `GoogleSignIn.initialize()`, que el Hub nunca llama, y se cuelga.
final List<Override> coachHubAccountDeletionOverrides = [
  accountDeletionReauthProvider.overrideWith(
    (ref) => (context) => coachHubReauth(
          authService: ref.read(authServiceProvider),
          user: ref.read(firebaseAuthProvider).currentUser,
          context: context,
        ),
  ),
  accountDeletionSignOutProvider.overrideWith(
    (ref) => () => ref.read(firebaseAuthProvider).signOut(),
  ),
];

/// Mismo criterio que mobile: el primer proveedor del usuario manda.
String _providerIdOf(User? user) => user != null && user.providerData.isNotEmpty
    ? user.providerData[0].providerId
    : 'password';

/// Re-autentica al PF en la web. `true` = confirmó, `false` = canceló.
/// Tira [AuthFailure] si falló (popup bloqueado, contraseña mal, otra cuenta).
///
/// Google y Apple: `reauthenticateWithPopup`. Va PRIMERO y sin `await` antes:
/// el navegador bloquea el popup si pierde el gesto del usuario.
/// Email: pide la contraseña en un diálogo.
Future<bool> coachHubReauth({
  required AuthService authService,
  required User? user,
  required BuildContext? context,
}) async {
  try {
    switch (_providerIdOf(user)) {
      case 'google.com':
        await authService.reauthenticateWithGooglePopup();
        return true;
      case 'apple.com':
        await authService.reauthenticateWithApplePopup();
        return true;
      default:
        if (context == null || !context.mounted) return false;
        final ok = await showTreinoDialog<bool>(
          context,
          barrierDismissible: false,
          builder: (_) => const _PasswordReauthDialog(),
        );
        return ok ?? false;
    }
  } on AuthFailure catch (e) {
    if (e.whenOrNull(signInCancelled: () => true) == true) return false;
    rethrow;
  }
}

/// Abre la confirmación de ELIMINAR CUENTA del Coach Hub.
Future<void> showEliminarCuentaDialog(BuildContext context) =>
    showTreinoDialog<void>(
      context,
      barrierDismissible: false,
      builder: (_) => const EliminarCuentaDialog(),
    );

/// Confirmación destructiva de ELIMINAR CUENTA del Coach Hub. Espejo web de
/// `EliminarCuentaSheet`: mismo notifier, mismo mapeo de errores, mismas reglas
/// de reintento (sin «Reintentar» si el servidor dijo `deletionNotAllowed`).
class EliminarCuentaDialog extends ConsumerWidget {
  const EliminarCuentaDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final state = ref.watch(accountDeletionNotifierProvider);

    // Éxito: el notifier ya cerró la sesión; el router del Hub manda al login.
    // Hay que cerrar el diálogo a mano (vive en el Navigator raíz) y bajar la
    // bandera, que en mobile consume la WelcomeScreen y acá nadie.
    ref.listen<bool>(accountDeletedFlagProvider, (_, deleted) {
      if (!deleted) return;
      ref.read(accountDeletedFlagProvider.notifier).state = false;
      Navigator.of(context).maybePop();
    });

    final failure = state.hasError ? state.error : null;
    final isLoading = state.isLoading;
    final locked = isLoading || ref.watch(accountDeletionBusyProvider);
    final canRetry =
        failure != null && failure != const AuthFailure.deletionNotAllowed();

    // `hasValue`, no `valueOrNull`: sin conteo cargado no se afirma ninguno.
    final impact = ref.watch(trainerUnlinkImpactProvider);
    final unlinkCount = impact.hasValue ? impact.requireValue : 0;

    final popupProvider = _popupProviderLabel(ref);

    final primaryLabel = failure == null
        ? l10n.eliminarCuentaSheetDeleteCta
        : (canRetry ? l10n.eliminarCuentaSheetRetryLabel : null);

    final bodyStyle = TextStyle(
      color: palette.textMuted,
      fontSize: AppTextSize.bodyDense,
    );

    return TreinoDialog(
      title: l10n.eliminarCuentaSheetTitle,
      destructive: true,
      loading: isLoading,
      errorMessage: failure == null ? null : _errorMessage(l10n, failure),
      primaryLabel: primaryLabel,
      onPrimaryTap: locked || primaryLabel == null
          ? null
          : () {
              final notifier =
                  ref.read(accountDeletionNotifierProvider.notifier);
              // Sin `await` antes: el popup de re-auth necesita el gesto.
              if (failure != null) {
                notifier.retry(context);
              } else {
                notifier.deleteAccount(context);
              }
            },
      secondaryLabel: l10n.eliminarCuentaSheetCancelCta,
      onSecondaryTap: isLoading ? null : () => Navigator.of(context).maybePop(),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: bodyStyle,
              children: [
                TextSpan(text: l10n.eliminarCuentaSheetBodyPrefix),
                TextSpan(
                  text: l10n.eliminarCuentaSheetBodyBold,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: l10n.eliminarCuentaSheetBodySuffix),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          // Baja ≠ reembolso: sin este aviso se cree que se devuelve la plata.
          Text(l10n.eliminarCuentaSheetSubscriptionNote, style: bodyStyle),
          if (unlinkCount > 0) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.eliminarCuentaSheetTrainerUnlinkNotice(unlinkCount),
              style: bodyStyle.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (popupProvider != null) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(l10n.eliminarCuentaWebPopupHint(popupProvider),
                style: bodyStyle),
          ],
          if (isLoading) ...[
            const SizedBox(height: AppSpacing.s12),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.eliminarCuentaSheetLoadingLabel,
                style: bodyStyle.copyWith(color: palette.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// «Google» / «Apple» si la re-auth va a abrir un popup; `null` con email.
  String? _popupProviderLabel(WidgetRef ref) {
    final id = _providerIdOf(ref.watch(firebaseAuthProvider).currentUser);
    return switch (id) {
      'google.com' => 'Google',
      'apple.com' => 'Apple',
      _ => null,
    };
  }
}

/// Mismo mapeo que `EliminarCuentaSheet`.
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

/// Pide la contraseña y re-autentica. Pop `true` si salió bien.
class _PasswordReauthDialog extends ConsumerStatefulWidget {
  const _PasswordReauthDialog();

  @override
  ConsumerState<_PasswordReauthDialog> createState() =>
      _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends ConsumerState<_PasswordReauthDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      await auth.reauthenticate(
        await auth.getPasswordCredential(password: password),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.userMessage;
          _loading = false;
        });
      }
    } catch (_) {
      // Sin esto `_loading` queda en true y el diálogo es inescapable
      // (barrera no descartable + CANCELAR deshabilitado mientras carga).
      if (mounted) {
        setState(() {
          _error = const AuthFailure.reAuthFailed().userMessage;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c),
        );
    return TreinoDialog(
      title: l10n.eliminarCuentaWebReauthTitle,
      loading: _loading,
      errorMessage: _error,
      primaryLabel: l10n.eliminarCuentaWebReauthCta,
      onPrimaryTap: _submit,
      secondaryLabel: l10n.eliminarCuentaSheetCancelCta,
      onSecondaryTap: _loading ? null : () => Navigator.of(context).pop(false),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.eliminarCuentaWebReauthPasswordBody,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyDense,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            enabled: !_loading,
            onSubmitted: (_) => _submit(),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: AppTextSize.body,
            ),
            decoration: InputDecoration(
              labelText: l10n.reAuthPasswordLabel,
              isDense: true,
              filled: true,
              fillColor: palette.bg,
              border: border(palette.border),
              enabledBorder: border(palette.border),
              focusedBorder: border(palette.accent),
              disabledBorder: border(palette.border),
            ),
          ),
        ],
      ),
    );
  }
}
