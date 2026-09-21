import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistence/shared_prefs_provider.dart';

/// Clave de la preferencia. El prefijo `privacy.` la agrupa con lo que venga
/// después (consentimientos, borrado) y la separa de `app.` (tema, UI).
const String kAnalyticsConsentKey = 'privacy.analytics_enabled';

/// Lee el consentimiento guardado. **Por defecto, habilitado.**
///
/// El default no es una decisión de producto tomada acá: es lo que la Política
/// de Privacidad ya dice. El consentimiento se presta al aceptarla en el alta,
/// y lo que la política promete —y la app no cumplía— es poder **revocarlo en
/// cualquier momento**. Este interruptor es la revocación, no el consentimiento.
///
/// Si algún día el consentimiento pasa a ser opt-in explícito, el cambio es acá
/// Y en el texto de la política, en el mismo PR. Uno sin el otro vuelve a dejar
/// al documento diciendo algo que el código no hace.
bool analyticsConsentFromPrefs(SharedPreferences prefs) =>
    prefs.getBool(kAnalyticsConsentKey) ?? true;

/// Cómo se le avisa a Firebase. Es un typedef y no una llamada directa para
/// que los tests puedan observarlo: `FirebaseAnalytics.instance` necesita a
/// Firebase inicializado, y un widget test no lo tiene.
typedef AnalyticsToggle = Future<void> Function(bool enabled);

Future<void> _aplicarEnFirebase(bool enabled) =>
    FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);

/// El aplicador real. Los tests lo sobreescriben.
final analyticsToggleProvider =
    Provider<AnalyticsToggle>((_) => _aplicarEnFirebase);

/// El interruptor de analítica, persistido y aplicado en el acto.
///
/// «En el acto» es el punto: la política dice «en cualquier momento», y un
/// interruptor que recién hace efecto al reiniciar la app no cumple eso. Por
/// eso [setEnabled] llama a Firebase además de guardar.
class AnalyticsConsentNotifier extends StateNotifier<bool> {
  AnalyticsConsentNotifier(this._prefs, this._toggle)
      : super(analyticsConsentFromPrefs(_prefs));

  final SharedPreferences _prefs;
  final AnalyticsToggle _toggle;

  /// Guarda y aplica. El estado se mueve primero para que el switch de la UI
  /// no quede trabado esperando a la red.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _prefs.setBool(kAnalyticsConsentKey, enabled);
    await _toggle(enabled);
  }
}

/// Provider reactivo del consentimiento.
///
/// Depende de que [sharedPreferencesProvider] esté resuelto antes de `runApp`
/// —igual que `themeModeProvider`— así que `.requireValue` es seguro acá.
final analyticsConsentProvider =
    StateNotifierProvider<AnalyticsConsentNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return AnalyticsConsentNotifier(prefs, ref.watch(analyticsToggleProvider));
});
