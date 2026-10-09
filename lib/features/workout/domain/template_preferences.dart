import 'package:freezed_annotation/freezed_annotation.dart';

import 'muscle_group.dart';
import 'routine_goal.dart';

part 'template_preferences.freezed.dart';
part 'template_preferences.g.dart';

/// What the athlete told the PLANTILLAS mini-onboarding (#635 PR#2): how much
/// they can train, what for, and which zones they want prioritised.
///
/// Persisted under `users/{uid}.templatePreferences`. PRIVATE data: it never
/// reaches `userPublicProfiles`, which carries its own explicit key allowlist
/// in firestore.rules — adding a field here cannot leak into it by accident.
/// `users/{uid}` has no `hasOnly` guard and no shape check on
/// `templatePreferences` (firestore.rules, `match /users/{uid}` → `allow
/// update`; re-verified 2026-10-09 when `goals` was added), so this field
/// needs no rules change; only the routine paths have that coupling.
///
/// ── Every field is nullable / empty-able on purpose ─────────────────────────
/// The flow is skippable at every step, and the issue is explicit that a
/// missing answer must read as NEUTRAL, never as an exclusion. A user who
/// skipped step 2 has no opinion about session length — that is not the same as
/// wanting 0 minutes, and the ranking (PR#3) must not treat it as one.
///
/// `toJson` va escrito a mano (`toJson: false`) porque tiene que espejar `goal`
/// para la 1.0; el generado sólo sabe escribir los campos del constructor.
@Freezed(toJson: false)
class TemplatePreferences with _$TemplatePreferences {
  const factory TemplatePreferences({
    /// 2..6. Null ⇒ not answered.
    int? daysPerWeek,

    /// 30 / 45 / 60 / 75, where 75 means "75 or more" — the handoff's last
    /// option is "75 MIN O MÁS". Stored as the lower bound so a future finer
    /// scale stays comparable. Null ⇒ not answered.
    int? minutesPerSession,

    /// Objetivos del atleta. Vacío ⇒ no respondió (NEUTRO, nunca excluye).
    ///
    /// ── Era uno solo, ahora son varios (2026-10-09, pedido del owner) ──────
    /// Antes esto era un `RoutineGoal? goal` a propósito: la idea era que "para
    /// qué entreno ahora" tenía una sola respuesta, y que lo multi-valor era
    /// cosa de la plantilla (`Routine.goals`, #635 PR#1). En uso real no se
    /// sostuvo: "salud y estética" es una respuesta legítima, y obligar a
    /// elegir una dejaba afuera a la mitad de lo que el atleta busca.
    ///
    /// ── Compatibilidad con la 1.0 de la App Store ─────────────────────────
    /// La 1.0 lee y escribe este mismo mapa y sólo conoce `goal`. Por eso:
    ///
    ///   * LEER: si `goals` falta o viene vacío y existe el `goal` legacy, vale
    ///     `[goal]` ([_readGoals]). Un atleta que respondió en la 1.0 no pierde
    ///     su respuesta al actualizar.
    ///   * ESCRIBIR: [toJson] manda `goals` Y `goal` = el primero elegido (o
    ///     null). La 1.0 sigue leyendo un valor con sentido.
    ///   * Si la 1.0 vuelve a guardar, escribe sólo `goal`. Ojo: NO reemplaza el
    ///     mapa. `UserRepository.update` persiste con `set(..., merge: true)` y
    ///     Firestore mergea los mapas anidados en profundidad, así que el
    ///     `goals` viejo SOBREVIVE junto al `goal` nuevo. La lectura lo
    ///     reconcilia con esta invariante: el cliente nuevo escribe SIEMPRE
    ///     `goal == goals.first` (o null si no hay). Si no coinciden, alguien
    ///     que sólo conoce `goal` editó después, y gana `goal` ([_readGoals]).
    ///
    /// [RoutineGoalListConverter] no es decoración: descarta los valores que no
    /// conoce en vez de tirar. Este modelo se decodifica como parte de
    /// `UserProfile`, así que un objetivo agregado por un build más nuevo, si
    /// tirara, rompería el stream del perfil entero en los clientes viejos y los
    /// mandaría a `/profile-unavailable` (#544).
    // ignore: invalid_annotation_target
    @JsonKey(readValue: _readGoals)
    @RoutineGoalListConverter()
    @Default(<RoutineGoal>[])
    List<RoutineGoal> goals,

    /// Canonical [MuscleGroup] keys (`chest`, `back`, `quads`…) — the app's one
    /// muscle vocabulary, reused rather than re-invented. Empty ⇒ no priority,
    /// which the handoff marks as explicitly optional ("Zonas a priorizar ·
    /// opcional").
    @Default(<String>[]) List<String> priorityMuscleGroups,
  }) = _TemplatePreferences;

  const TemplatePreferences._();

  factory TemplatePreferences.fromJson(Map<String, Object?> json) =>
      _$TemplatePreferencesFromJson(json);

  /// Forma persistida. Ver la nota de compatibilidad en [goals]: además de
  /// `goals` escribe `goal` = el primero, para que la 1.0 lo siga leyendo.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'daysPerWeek': daysPerWeek,
        'minutesPerSession': minutesPerSession,
        'goals': const RoutineGoalListConverter().toJson(goals),
        'goal': goals.firstOrNull?.wireKey,
        'priorityMuscleGroups': priorityMuscleGroups,
      };

  /// True when the athlete answered nothing at all.
  ///
  /// Used to decide whether there is anything worth writing: SALTAR on step 1
  /// should not put an all-null map on the user's document just to prove the
  /// flow ran. The "did they see it" signal is `onboardingSeen`, not this.
  bool get isEmpty =>
      daysPerWeek == null &&
      minutesPerSession == null &&
      goals.isEmpty &&
      priorityMuscleGroups.isEmpty;

  /// The priority zones resolved to their canonical groups, dropping anything
  /// unknown.
  ///
  /// Unknown keys are skipped rather than surfaced: a value written by a newer
  /// build must degrade to "one less priority", never to a crash or an empty
  /// grid.
  List<MuscleGroup> get priorityGroups => priorityMuscleGroups
      .map(MuscleGroup.fromKey)
      .whereType<MuscleGroup>()
      .toList(growable: false);
}

/// Lee `goals` reconciliándolo con el `goal` legacy.
///
/// Invariante del cliente nuevo: escribe `goal == goals.first` (null si vacío).
///  * `goals` con datos y `goal` coincide con su primero (o la clave `goal`
///    no existe) ⇒ vale `goals`.
///  * `goals` con datos y `goal` difiere (incluido null o un valor que este
///    build no conoce) ⇒ editó la 1.0 después: vale `goal` ⇒ `[goal]`, o `[]`
///    si era null/desconocido (el converter descarta lo desconocido).
///  * `goals` falta o vacío ⇒ `[goal]` si existe.
///
/// Devuelve la forma CRUDA (lista de wire keys); el filtrado de lo desconocido
/// lo hace [RoutineGoalListConverter] después. Un `goal` que no es `String` se
/// ignora: mejor "sin objetivo" que un perfil que no carga.
Object? _readGoals(Map<dynamic, dynamic> json, String key) {
  final goals = json[key];
  final legacy = json['goal'];
  final legacyKey = legacy is String ? legacy : null;
  if (goals is List && goals.isNotEmpty) {
    // Sin clave `goal` no hay edición legacy que reconciliar.
    if (!json.containsKey('goal') || legacy == goals.first) return goals;
    return legacyKey == null ? <String>[] : <String>[legacyKey];
  }
  if (legacyKey != null) return <String>[legacyKey];
  // Cualquier otra forma (un String suelto, un mapa) cae a vacío: el
  // generado hace `as List?` y tiraría.
  return goals is List ? goals : null;
}
