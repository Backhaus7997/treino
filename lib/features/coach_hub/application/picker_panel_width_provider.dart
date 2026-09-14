import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/shared_prefs_provider.dart';

/// Ancho del panel lateral del picker de ejercicios, persistido por navegador
/// vía `shared_preferences` — mismo criterio que el colapso del sidebar
/// (ADR-CHW-003): es una preferencia de LAYOUT de quien está sentado ahí, no
/// un dato del negocio, así que no viaja a Firestore.
const String _kStorageKey = 'coach_hub.picker_panel.width';

/// Piso. Abajo de esto la fila del ejercicio deja de entrar: nombre + badge
/// «MÍO» + los tres controles de 24 px se pisan y el nombre parte en tres
/// líneas.
const double kAnchoPanelPickerMin = 340;

/// Techo absoluto. Más que esto y el panel deja de ser un panel: en un
/// ultrawide se comería la pantalla aunque a la rutina le sobre lugar.
const double kAnchoPanelPickerMax = 640;

/// Lo que la RUTINA no cede nunca, en px.
///
/// No es un número elegido: es el que YA se envía. A 1280 de viewport —el piso
/// donde el panel aparece (ADR-CHW-004)— con el sidebar de 240 afuera quedan
/// 1040, el panel se lleva 400 y a la rutina le quedan estos 640. O sea que el
/// tope de arrastre nunca deja el editor peor de lo que hoy ya funciona.
const double kAnchoMinimoRutina = 640;

/// Ancho por defecto. Se mantiene el valor histórico del panel fijo (#860)
/// para que a nadie le cambie la pantalla sin pedirlo; a partir de ahí, lo
/// mueve quien quiera.
const double kAnchoPanelPickerDefault = 400;

/// El máximo REAL para un ancho disponible dado.
///
/// Ojo con de dónde sale `anchoDisponible`: adentro de una sección
/// `MediaQuery` miente, porque el sidebar ya se descontó y además colapsa de
/// 240 a 72 sin que el viewport cambie. Va de un `LayoutBuilder`.
double maxAnchoPanelPicker(double anchoDisponible) => math.max(
      kAnchoPanelPickerMin,
      math.min(kAnchoPanelPickerMax, anchoDisponible - kAnchoMinimoRutina),
    );

/// Notifier del ancho. Inicializa desde prefs y persiste en cada arrastre.
///
/// Las prefs entran como NULLABLE, y no es una concesión al test: el sidebar
/// puede permitirse `requireValue` porque el shell no dibuja hasta tenerlas,
/// pero un widget de sección que las exige se lleva puesto cualquier árbol que
/// lo monte antes —o sin shell— con un `Bad state` en vez de degradar. Sin
/// prefs el panel arranca en el default y no persiste; con ellas, todo igual.
class PickerPanelWidthNotifier extends StateNotifier<double> {
  PickerPanelWidthNotifier(this._prefs)
      : super(_prefs?.getDouble(_kStorageKey) ?? kAnchoPanelPickerDefault);

  final SharedPreferences? _prefs;

  /// Suma [delta] px al ancho y lo acota contra [maxAncho].
  ///
  /// El clamp va acá y no en el widget a propósito: si el PF ensancha el panel
  /// en un monitor grande y después abre el editor en la laptop, el valor
  /// guardado excede lo que entra. Acotar sólo al dibujar dejaría el número
  /// malo en prefs; acotarlo también al escribir lo corrige la primera vez que
  /// lo toca.
  void ajustar(double delta, {required double maxAncho}) {
    final nuevo = (state + delta).clamp(kAnchoPanelPickerMin, maxAncho);
    if (nuevo == state) return;
    state = nuevo;
    _prefs?.setDouble(_kStorageKey, nuevo);
  }
}

final pickerPanelWidthProvider =
    StateNotifierProvider<PickerPanelWidthNotifier, double>((ref) {
  return PickerPanelWidthNotifier(
    ref.watch(sharedPreferencesProvider).valueOrNull,
  );
});
