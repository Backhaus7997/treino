/// El único lugar donde la app pregunta la hora.
///
/// ## Por qué existe
///
/// `DateTime.now()` es una dependencia global no inyectada: cualquier widget
/// que la llame queda **imposible de fotografiar dos veces igual**. El gate de
/// regresión visual del Coach Hub (#761) necesita exactamente eso — que la
/// misma pantalla, con el mismo seed, rinda los mismos píxeles hoy y en tres
/// meses. Con `DateTime.now()` en el camino de render no se puede: el filtro
/// de "próximas sesiones" del dashboard descarta turnos según la hora real a
/// la que corra CI, y el golden pasa o falla según el reloj del runner.
///
/// Un golden que cambia porque cambió la fecha no es un gate, es ruido. Y el
/// ruido en un gate termina siempre igual: alguien lo desactiva.
///
/// Este es el mismo movimiento que ya hizo `resolveBarMetrics`
/// (`lib/core/widgets/treino_bottom_bar.dart`): sacar la dependencia
/// intestable a un seam explícito y dejar la decisión testeable con datos
/// fijos.
///
/// ## Cómo se usa
///
/// En producción es un passthrough — mismo costo, mismo valor, misma zona
/// horaria que `DateTime.now()`:
///
/// ```dart
/// final ahora = AppClock.now();
/// ```
///
/// En un test que necesita píxeles o strings estables:
///
/// ```dart
/// setUp(() => AppClock.freeze(DateTime(2026, 3, 17, 10, 30)));
/// tearDown(AppClock.unfreeze);
/// ```
///
/// ## Qué NO hace
///
/// No es un reloj virtual: no avanza, no se puede adelantar, no interactúa con
/// `fakeAsync`. Congelado devuelve **siempre el mismo instante**. Si un test
/// necesita ver el paso del tiempo, congelá de nuevo en otro instante — que el
/// cambio de hora sea una línea visible del test y no un efecto de fondo.
///
/// No reemplaza a [argentinaNow] ni a [nowWall]: esos dos siguen siendo la
/// puerta correcta para calendario ART y para wall-clock ADR-7
/// respectivamente. Los dos leen de acá, así que congelar [AppClock] los
/// congela a los dos.
library;

import 'package:flutter/foundation.dart';

/// Reloj del proceso. Ver el dartdoc de la librería.
abstract final class AppClock {
  /// Instante fijo mientras el reloj está congelado; `null` en producción.
  ///
  /// Es local-flagged (no UTC), igual que `DateTime.now()`, para que los
  /// callers que hacen `.toUtc()` o `.toLocal()` se comporten idéntico con y
  /// sin congelar.
  static DateTime? _frozen;

  /// "Ahora", local-flagged. Drop-in de `DateTime.now()`.
  static DateTime now() => _frozen ?? DateTime.now();

  /// Congela el reloj en [instant] hasta que alguien llame a [unfreeze].
  ///
  /// [instant] debe ser local (no UTC): este reloj sustituye a
  /// `DateTime.now()`, que devuelve local. Pasar un UTC-flagged rompería a
  /// todo caller que haga `.toUtc()` — se restaría el offset dos veces.
  @visibleForTesting
  static void freeze(DateTime instant) {
    assert(
      !instant.isUtc,
      'AppClock.freeze() espera un DateTime local (no UTC): reemplaza a '
      'DateTime.now(), que devuelve local. Con un UTC-flagged, los callers '
      'que hacen .toUtc() restan el offset dos veces.',
    );
    _frozen = instant;
  }

  /// Devuelve el reloj a la hora real. Idempotente.
  @visibleForTesting
  static void unfreeze() => _frozen = null;

  /// `true` si hay un instante congelado. Para que un harness pueda afirmar
  /// que el seam está activo antes de comparar píxeles, en vez de confiar en
  /// que alguien llamó a [freeze].
  @visibleForTesting
  static bool get isFrozen => _frozen != null;
}
