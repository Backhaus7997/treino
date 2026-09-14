import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notification_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../onboarding/application/onboarding_providers.dart';
import '../../profile/application/user_providers.dart';

/// App-session flag tracking whether the gate has already requested permission.
/// Lives at the root [ProviderScope] so widget re-mounts (tab nav, hot reload,
/// HomeScreen rebuilds) don't re-fire the prompt. Resets only on app cold-start
/// (new ProviderScope). Visible for testing so test setups can reset isolation.
@visibleForTesting
final permissionGateAttemptedProvider = StateProvider<bool>((ref) => false);

/// `true` mientras el prompt del SISTEMA OPERATIVO está en pantalla.
///
/// Distinto de [permissionGateAttemptedProvider], que se pone en `true` ANTES
/// del `await` —para cerrar la ventana de re-entrada del propio gate— y por lo
/// tanto no sirve para que OTRO gate sepa si el alert todavía está arriba.
/// Cualquier gate de `/home` que vaya a mostrar algo modal tiene que esperar
/// [permissionPromptSettledProvider], no el flag de "ya intenté".
@visibleForTesting
final permissionPromptInFlightProvider = StateProvider<bool>((ref) => false);

/// El prompt de permisos ya terminó: se intentó Y no quedó ninguno en pantalla.
///
/// #627 se arregló haciendo que este gate esperara a `onboardingBlocksProvider`.
/// Ese provider mide el tour de onboarding y NADA más, así que no dice nada
/// sobre los otros prompts de `/home`. Dos gates hermanos que sólo miran esa
/// condición encolan su `addPostFrameCallback` en el MISMO frame y el segundo
/// aparece debajo del alert del SO — el mismo patrón del #627, con otro par de
/// widgets.
final permissionPromptSettledProvider = Provider<bool>((ref) {
  return ref.watch(permissionGateAttemptedProvider) &&
      !ref.watch(permissionPromptInFlightProvider);
});

/// Invisible widget that requests notification permission exactly once per
/// app session, and only after the user has completed profile setup.
///
/// Placement: mount as a sibling widget inside the home shell build tree
/// ([HomeScreen]). It renders [SizedBox.shrink()] — zero layout impact.
///
/// Gate condition (ADR-PN-012): permission is requested when ALL are true:
/// - User is authenticated (authState non-null).
/// - `userProfile.displayName != null` (profile setup is complete).
/// - [permissionGateAttemptedProvider] is `false` (not yet requested in this
///   app session).
///
/// Denial path: the OS prompt result is logged and swallowed — no retry,
/// no SnackBar, no navigation. REQ-PN-PERM-002.
///
/// REQ-PN-PERM-001, REQ-PN-PERM-002, SCENARIO-659..663, ADR-PN-012.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key});

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final setupDone = profile?.displayName != null;
    final attempted = ref.watch(permissionGateAttemptedProvider);
    // #627: both this gate and the onboarding card mount on /home and both fire
    // post-frame on its first render. Without the wait, the OS alert lands on
    // top of the card — green in every widget test, broken on a device.
    final onboardingPending = ref.watch(onboardingBlocksProvider);

    if (setupDone && !attempted && !onboardingPending) {
      // Defer provider mutation + side-effect to after frame: Riverpod
      // forbids modifying providers from within a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(permissionGateAttemptedProvider)) return;
        ref.read(permissionGateAttemptedProvider.notifier).state = true;
        _requestPermission();
      });
    }

    return const SizedBox.shrink();
  }

  Future<void> _requestPermission() async {
    // Se levanta ANTES del await y se baja en el `finally`: es la ventana en
    // la que el alert del SO está efectivamente en pantalla, y es lo que los
    // otros gates de /home tienen que respetar.
    ref.read(permissionPromptInFlightProvider.notifier).state = true;
    try {
      final fcm = ref.read(fcmServiceProvider);
      final settings = await fcm.requestPermission();
      debugPrint(
        '[fcm] permission status: ${settings.authorizationStatus}',
      );

      // Re-trigger init() so the token gets registered now that APNS has
      // been provisioned. Without this, the initial init() at sign-in
      // failed silently (no APNS) and the user never receives notifications
      // until the next sign-in cycle. SCENARIO-687.
      final status = settings.authorizationStatus;
      final granted = status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
      if (!granted) return;

      final user = await ref.read(authStateChangesProvider.future);
      if (user == null) return;
      await fcm.init(user.uid);
    } catch (e) {
      // Swallow errors (e.g. platform exceptions) — denial is graceful.
      // i18n: Fase 6 Etapa 2
      debugPrint('[fcm] requestPermission error: $e');
    } finally {
      // En el finally y no al final del try: si `requestPermission` tira, el
      // alert ya no está, y dejar el flag arriba colgaría a los otros gates
      // para toda la sesión.
      if (ref.context.mounted) {
        ref.read(permissionPromptInFlightProvider.notifier).state = false;
      }
    }
  }
}
