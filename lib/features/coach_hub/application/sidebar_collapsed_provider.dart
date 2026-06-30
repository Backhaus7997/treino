import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_prefs_provider.dart';

/// Estado colapsado/expandido del sidebar del Coach Hub web, persistido por
/// navegador vía `shared_preferences` (ADR-CHW-003).
///
/// `false` = expandido (264 px) · `true` = colapsado (72 px). El default de
/// primera visita es expandido. En web `shared_preferences` escribe a
/// `window.localStorage`, por lo que el estado sobrevive al reload y es
/// per-browser (colapsar en la laptop no colapsa en el desktop).
const String _kStorageKey = 'coach_hub.sidebar.collapsed';

/// Notifier del estado colapsado. Inicializa desde prefs y persiste en cada
/// `toggle()`.
class SidebarCollapsedNotifier extends StateNotifier<bool> {
  SidebarCollapsedNotifier(this._prefs)
      : super(_prefs.getBool(_kStorageKey) ?? false);

  final SharedPreferences _prefs;

  /// Invierte el estado y lo persiste (fire-and-forget desde la UI).
  Future<void> toggle() async {
    state = !state;
    await _prefs.setBool(_kStorageKey, state);
  }
}

/// Estado colapsado del sidebar. Depende de [sharedPreferencesProvider] ya
/// resuelto; el shell gatea el render hasta que las prefs estén disponibles.
final sidebarCollapsedProvider =
    StateNotifierProvider<SidebarCollapsedNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return SidebarCollapsedNotifier(prefs);
});
