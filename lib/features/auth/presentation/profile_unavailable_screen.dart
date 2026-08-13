import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/auth_providers.dart';
import 'widgets/auth_pill_button.dart';

/// Estado degradado "autenticado pero sin perfil accesible" (issue #544).
///
/// Se llega acá SOLO vía el redirect del router: cuando la sesión de auth es
/// válida pero el stream de `userProfileProvider` terminó en error
/// (permission-denied por backend switch, rules regression, cuenta
/// inaccesible, quota…). Sin esta pantalla el usuario quedaba en un limbo de
/// skeletons perpetuos en Home/Perfil, sin mensaje ni salida visible.
///
/// Ofrece las dos únicas salidas reales del estado:
/// - **Reintentar** → invalida el provider; si el perfil resuelve, el
///   redirect del router saca al usuario solo (recovery exit → /home).
/// - **Cerrar sesión** → auth pasa a null y el redirect manda a /welcome.
class ProfileUnavailableScreen extends ConsumerWidget {
  const ProfileUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Mientras el reintento está en vuelo el provider vuelve a loading —
    // el pill muestra su spinner. Si falla de nuevo, vuelve a ser tapeable.
    final retrying = ref.watch(userProfileProvider).isLoading;
    final signingOut = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(TreinoIcon.warning, size: 48, color: palette.textMuted),
                const SizedBox(height: 20),
                Text(
                  l10n.coachProfileErrorLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 28),
                AuthPillButton(
                  label: l10n.coachRetryLabel,
                  isLoading: retrying,
                  showArrow: false,
                  onPressed: () => ref.invalidate(userProfileProvider),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: signingOut
                      ? null
                      : () => ref.read(authNotifierProvider.notifier).signOut(),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textMuted,
                  ),
                  icon: const Icon(TreinoIcon.signOut, size: 18),
                  label: Text(l10n.authProfileSignOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
