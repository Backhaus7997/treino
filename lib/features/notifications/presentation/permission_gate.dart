import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notification_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';

/// App-session flag tracking whether the gate has already requested permission.
/// Lives at the root [ProviderScope] so widget re-mounts (tab nav, hot reload,
/// HomeScreen rebuilds) don't re-fire the prompt. Resets only on app cold-start
/// (new ProviderScope). Visible for testing so test setups can reset isolation.
@visibleForTesting
final permissionGateAttemptedProvider = StateProvider<bool>((ref) => false);

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

    if (setupDone && !attempted) {
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
    }
  }
}
