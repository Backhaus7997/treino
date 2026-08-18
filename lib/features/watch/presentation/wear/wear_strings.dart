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

  /// Por qué no aparece "Terminar" todavía.
  ///
  /// Pedido del dueño, documentado en `WorkoutView.swift`: el botón sólo sale
  /// con TODAS las series de TODOS los ejercicios marcadas. Tenerlo siempre a
  /// la vista invita a cerrar el entreno de más, sobre todo con la muñeca
  /// mojada y el botón a un toque del último círculo que se marcó.
  static const finishHint = 'Marcá todas las series para terminar';

  /// Cierra el entreno como COMPLETADO. Sólo aparece con todo marcado.
  static const finish = 'Terminar';

  /// La salida para un entreno que no se puede completar.
  ///
  /// Chico, gris y sin tinte destructivo a propósito: existe para una lesión o
  /// un imprevisto, no para usarse por costumbre. Sin esto, el atleta que se
  /// lastima sin el teléfono a mano deja la sesión abierta para siempre.
  static const abandon = 'Abandonar';

  /// La confirmación. Abandonar no se deshace.
  static const abandonConfirm = '¿Abandonar el entreno?';
  static const abandonYes = 'Sí, abandonar';
  static const abandonNo = 'Seguir entrenando';

  /// NO existe un placeholder de "sin dato" a propósito. Cuando no hay pulso ni
  /// calorías no se dibuja NADA: ni un guion, ni un cero, ni un aviso. Una
  /// lectura negada por el atleta es indistinguible de "todavía no hay datos",
  /// así que cualquier texto sería adivinar. Ver `WorkoutView.swift`.

  /// Estado inicial mientras se resuelve el entreno del día.
  static const loading = 'Cargando';

  // ── Emparejamiento ──────────────────────────────────────────────────────
  static const openOnPhone =
      'Abrí TREINO en el teléfono para vincular el reloj';
  static const linking = 'Vinculando…';
  static const linkFailed = 'No se pudo vincular. Abrí TREINO en el teléfono.';

  // ── HOY ─────────────────────────────────────────────────────────────────
  static const today = 'HOY';
  static const start = 'Empezar';
  static const exercises = 'EJERCICIOS';
  static const loadingRoutine = 'Cargando tu rutina…';
  static const routineLoadFailed = 'No se pudo cargar tu rutina';
  static const noExercisesThisWeek = 'Sin ejercicios esta semana';

  /// Resolvió bien y no hay entreno: el atleta no tiene plan activo.
  ///
  /// Manda a PLANES y no al teléfono porque activar se puede desde la muñeca:
  /// es la página de al lado. Mandarlo al celular sería pedirle que vaya a
  /// buscarlo teniendo la solución a un deslizamiento.
  static const noActivePlan = 'Sin plan activo. Elegí uno en PLANES.';

  /// Abreviatura de semana. Sólo se muestra en planes periodizados.
  static const weekAbbrev = 'Sem';

  // ── Listas laterales ────────────────────────────────────────────────────
  static const myPlans = 'MIS PLANES';
  static const templates = 'PLANTILLAS';
  static const noPlans = 'No tenés planes cargados';
  static const noTemplates = 'No hay plantillas disponibles';
  static const loadFailed = 'No se pudo cargar';

  // ── Detalle de rutina ───────────────────────────────────────────────────
  static const activate = 'Activar';

  /// Por qué «Empezar» y «Activar» son cosas distintas.
  ///
  /// Texto tomado literal de `RoutineDetailView.swift`: el atleta tiene que
  /// entender que probar una plantilla NO le pisa el plan que le armó su PF.
  static const hintPlans =
      '«Empezar» no cambia tu rutina activa. «Activar» sí, también en el teléfono.';
  static const hintTemplates =
      'Entrenás esta plantilla sin cambiar tu rutina activa.';
}
