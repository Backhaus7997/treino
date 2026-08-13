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

  /// Acción para saltear lo que queda de descanso. Igual que en watchOS.
  static const restSkip = 'Saltar';

  /// Unidad de ritmo cardíaco. Coincide con la del reloj de Apple
  /// (`WorkoutView.swift`), para que el atleta lea lo mismo en los dos.
  static const bpmUnit = 'lpm';

  /// Unidad de energía activa.
  static const kcalUnit = 'kcal';

  /// Series marcadas que todavía no subieron a Firestore.
  static const pendingUpload = 'sin subir';

  /// Por qué no aparece "Terminar" todavía.
  ///
  /// Pedido del dueño, documentado en `WorkoutView.swift`: el botón sólo sale
  /// con TODAS las series de TODOS los ejercicios marcadas. Tenerlo siempre a
  /// la vista invita a cerrar el entreno de más, sobre todo con la muñeca
  /// mojada y el botón a un toque del último círculo que se marcó.
  static const finishHint = 'Marcá todas las series para terminar';

  /// NO existe un placeholder de "sin dato" a propósito. Cuando no hay pulso ni
  /// calorías no se dibuja NADA: ni un guion, ni un cero, ni un aviso. Una
  /// lectura negada por el atleta es indistinguible de "todavía no hay datos",
  /// así que cualquier texto sería adivinar. Ver `WorkoutView.swift`.

  /// Estado inicial mientras se resuelve el entreno del día.
  static const loading = 'Cargando';
}
