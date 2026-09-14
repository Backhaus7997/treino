import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/shared_prefs_provider.dart';
import '../data/pending_invite_store.dart';

/// La invitación guardada a disco, esperando a que haya sesión para aplicarse.
///
/// Devuelve `null` —y no explota— cuando `SharedPreferences` todavía no
/// resolvió. En producción está resuelto antes de `runApp` y entra por override
/// (ADR-LM-009), así que ese `null` no se ve; pero CUALQUIER widget test que
/// monte la home sin overridearlo lo pega, y `requireValue` ahí tira un
/// `StateError` que tumba la pantalla entera.
///
/// Degradar es lo correcto y no una concesión al test: una invitación no es
/// precondición de nada. Es la misma doctrina que [InviteGate] hereda de
/// [OnboardingGate] — el peor caso tiene que ser que el diálogo no aparezca,
/// nunca que la app se rompa por él.
final pendingInviteStoreProvider = Provider<PendingInviteStore?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return prefs == null ? null : PendingInviteStore(prefs);
});
