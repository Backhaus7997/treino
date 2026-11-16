import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/emuladores.dart' show kUsaEmuladores;
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

/// Lo que de verdad se le pide a Firebase Analytics: el [consentimiento], salvo
/// con `USE_EMULATOR`, donde la colección queda apagada (#1698).
///
/// Analytics no tiene emulador. Con los demás servicios redirigidos
/// ([conectarEmuladores]), seguía mandando eventos al proyecto real —que es
/// PRODUCCIÓN, `treino-dev`—: la QA E2E del 2026-11-06 midió 1068 requests en
/// una pasada, y cada corrida de dev o QA ensuciaba los datos reales.
///
/// Es una expresión sobre una `const` (el default de [emulador]) y NO una
/// llamada con un `false` literal: en un build normal se pliega
/// a [consentimiento] y no deja nada, como el `if (kUsaEmuladores)` de los
/// entry points (#1709); y el guard de `analytics_consent_scan_test` prohíbe los
/// literales, porque la analítica tiene que seguir derivando del consentimiento
/// del usuario. Sólo APAGA: nunca prende algo que el usuario revocó.
///
/// La usan los dos entry points y [_aplicarEnFirebase], así que el interruptor
/// de Privacidad tampoco puede volver a prenderla en modo emulador. Lo que
/// MUESTRA el interruptor sigue siendo la preferencia guardada
/// ([analyticsConsentFromPrefs]), no esto.
///
/// [emulador] existe para que un test lo fuerce; nadie más lo pasa.
bool analyticsEfectiva(
  bool consentimiento, {
  @visibleForTesting bool emulador = kUsaEmuladores,
}) =>
    consentimiento && !emulador;

/// Cómo se le avisa a Firebase. Es un typedef y no una llamada directa para
/// que los tests puedan observarlo: `FirebaseAnalytics.instance` necesita a
/// Firebase inicializado, y un widget test no lo tiene.
typedef AnalyticsToggle = Future<void> Function(bool enabled);

Future<void> _aplicarEnFirebase(bool enabled) => FirebaseAnalytics.instance
    .setAnalyticsCollectionEnabled(analyticsEfectiva(enabled));

/// El aplicador real. Los tests lo sobreescriben.
final analyticsToggleProvider =
    Provider<AnalyticsToggle>((_) => _aplicarEnFirebase);

/// Cómo se persiste. Segundo seam, por el mismo motivo que [AnalyticsToggle]:
/// un test tiene que poder hacer fallar la escritura, y con un
/// `SharedPreferences` real no se puede.
typedef ConsentWriter = Future<bool> Function(bool enabled);

/// El interruptor de analítica, persistido y aplicado en el acto.
///
/// «En el acto» es el punto: la política dice «en cualquier momento», y un
/// interruptor que recién hace efecto al reiniciar la app no cumple eso.
class AnalyticsConsentNotifier extends StateNotifier<bool> {
  AnalyticsConsentNotifier(this._escribir, this._toggle,
      {required bool inicial})
      : super(inicial);

  final ConsentWriter _escribir;
  final AnalyticsToggle _toggle;

  /// Apaga o prende, y deja los TRES lugares de acuerdo: lo que muestra el
  /// switch, lo que hace Firebase y lo que queda guardado.
  ///
  /// El orden no es casual. Primero se le avisa a Firebase, que es lo único
  /// que de verdad corta la recolección; recién después se guarda. Al revés
  /// —como estaba— un fallo al guardar dejaba el switch en «apagado» con la
  /// recolección viva, que es la peor combinación posible: el usuario cree que
  /// revocó y no revocó.
  ///
  /// Si algo falla se **vuelve atrás en los tres**, incluido el switch. Que
  /// rebote a la vista es la señal honesta de que no tomó. Dejarlo en el valor
  /// nuevo seria un cartel que miente (AGENTS.md §11.1).
  ///
  /// `setBool` devuelve un `bool` y **puede devolver `false` sin tirar**: eso
  /// tambien es un fallo, y tratarlo como exito hace que al proximo arranque
  /// la analitica vuelva sola sin que nadie se entere.
  Future<void> setEnabled(bool enabled) async {
    final anterior = state;
    if (anterior == enabled) return;

    state = enabled;
    // Si el toggle NO llegó a aplicarse, Firebase sigue en `anterior` y
    // revertirlo sería una llamada al pedo. Sólo se revierte lo que cambió.
    var aplicado = false;
    try {
      await _toggle(enabled);
      aplicado = true;
      if (!await _escribir(enabled)) {
        throw StateError('SharedPreferences no pudo guardar el consentimiento');
      }
    } catch (_) {
      state = anterior;
      if (aplicado) {
        // Mejor esfuerzo: si esto también falla, el estado ya volvió al valor
        // anterior y la próxima interacción reintenta. El error no se traga en
        // silencio — queda el switch rebotando, que es visible.
        try {
          await _toggle(anterior);
        } catch (_) {
          // nada más que hacer desde acá
        }
      }
    }
  }
}

/// Provider reactivo del consentimiento.
///
/// Depende de que [sharedPreferencesProvider] esté resuelto antes de `runApp`
/// —igual que `themeModeProvider`— así que `.requireValue` es seguro acá.
final analyticsConsentProvider =
    StateNotifierProvider<AnalyticsConsentNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return AnalyticsConsentNotifier(
    (v) => prefs.setBool(kAnalyticsConsentKey, v),
    ref.watch(analyticsToggleProvider),
    inicial: analyticsConsentFromPrefs(prefs),
  );
});
