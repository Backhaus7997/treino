/// Textos de la UI del companion de Wear OS.
///
/// La regla 3 del design system dice: *"Tab labels, feature names, mensajes —
/// centralizar en constantes o (cuando llegue Fase 6) en archivos de
/// localización (`lib/l10n/`)"*. Esto es la rama de constantes.
///
/// **Deuda consciente**: cuando el companion deje de ser un slice y pase a
/// producto, estas claves tienen que mudarse a `lib/l10n/*.arb` como el resto
/// de la app. No se hizo acá porque los ARB los toca otra sesión en paralelo y
/// pisarlos genera conflictos caros de resolver.
class WearStrings {
  const WearStrings._();

  /// Título de la pantalla de descanso. UPPERCASE porque es heading —
  /// Barlow Condensed 700, según el design system.
  static const restTitle = 'DESCANSO';

  /// Cuando el descanso terminó y toca volver a la barra.
  static const restDone = '¡DALE!';

  /// Acción para saltear lo que queda de descanso.
  static const restSkip = 'Saltear';

  /// Acción para marcar la serie y arrancar el descanso.
  static const markSet = 'Marcar serie';

  /// Unidad de ritmo cardíaco. Coincide con la del reloj de Apple
  /// (`WorkoutView.swift`), para que el atleta lea lo mismo en los dos.
  static const bpmUnit = 'lpm';

  /// Unidad de energía activa.
  static const kcalUnit = 'kcal';

  /// Placeholder cuando un dato de esfuerzo está vencido o no llegó todavía.
  /// Se muestra ESTO y no el último valor conocido: un pulso viejo presentado
  /// como actual es peor que no mostrar nada.
  static const noData = '--';

  /// Estado inicial mientras se resuelve el entreno del día.
  static const loading = 'Cargando';
}
