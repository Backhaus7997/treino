/// Canonical muscle taxonomy shared by the stock catalogue and a trainer's
/// custom exercises. ONE vocabulary across the app: creation dropdown, the
/// exercise-picker muscle filter, and (via [fromKey]) the Insights rollup.
///
/// Each group carries a stable [key] (persisted in Firestore — these match the
/// English keys the seed catalogue already uses, so no stock migration is
/// needed) and a Spanish [label] for the UI.
///
/// Older custom exercises persisted Spanish labels ('Pecho', 'Espalda alta',
/// 'Gemelos', …) that never mapped to any filter group — they were invisible.
/// [fromKey] canonicalises those legacy values too, so nothing stays orphaned.
enum MuscleGroup {
  pecho('chest', 'Pecho', 'assets/muscles/chest.png'),
  espalda('back', 'Espalda', 'assets/muscles/back.png'),
  hombros('shoulders', 'Hombros', 'assets/muscles/shoulders.png'),
  biceps('biceps', 'Bíceps', 'assets/muscles/biceps.png'),
  triceps('triceps', 'Tríceps', 'assets/muscles/triceps.png'),
  cuadriceps('quads', 'Cuádriceps', 'assets/muscles/quads.png'),
  isquiotibiales(
      'hamstrings', 'Isquiotibiales', 'assets/muscles/hamstrings.png'),
  gluteos('glutes', 'Glúteos', 'assets/muscles/glutes.png'),
  pantorrilla('calves', 'Pantorrilla', 'assets/muscles/calves.png'),
  abdominales('core', 'Abdominales', 'assets/muscles/core.png'),
  cardio('cardio', 'Cardio', null),
  cuerpoCompleto('full_body', 'Cuerpo completo', null);

  const MuscleGroup(this.key, this.label, this.assetPath);

  /// Canonical key persisted in Firestore (shared by stock + custom exercises).
  final String key;

  /// Spanish display label (creation dropdown, filter chips, row subtitle).
  final String label;

  /// Optional PNG illustration under `assets/muscles/`. `null` for groups with
  /// no artwork yet (cardio, full body) — the UI falls back to an icon.
  final String? assetPath;

  /// Canonical order for the creation dropdown and the muscle filter — matches
  /// the enum declaration order above.
  static const List<MuscleGroup> displayOrder = MuscleGroup.values;

  /// Resolves any stored or legacy muscle string to its canonical group.
  ///
  /// Handles canonical keys (`chest`…), English aliases (`abs`, `fullbody`),
  /// and the Spanish labels the old custom-exercise editor persisted
  /// (`Pecho`, `Espalda alta`, `Dorsales`, `Gemelos`, `Antebrazos`, …).
  /// Returns `null` for unknown values or the legacy catch-all `Otro`.
  static MuscleGroup? fromKey(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    return switch (v) {
      // ── Canonical keys (stock catalogue + new custom exercises) ──────────
      'chest' => MuscleGroup.pecho,
      'back' => MuscleGroup.espalda,
      'shoulders' => MuscleGroup.hombros,
      'biceps' => MuscleGroup.biceps,
      'triceps' => MuscleGroup.triceps,
      'quads' => MuscleGroup.cuadriceps,
      'hamstrings' => MuscleGroup.isquiotibiales,
      'glutes' => MuscleGroup.gluteos,
      'calves' => MuscleGroup.pantorrilla,
      'core' || 'abs' => MuscleGroup.abdominales,
      'cardio' => MuscleGroup.cardio,
      'full_body' || 'fullbody' => MuscleGroup.cuerpoCompleto,
      // ── Legacy Spanish labels (old custom-exercise editor) ───────────────
      'pecho' => MuscleGroup.pecho,
      'espalda' ||
      'espalda alta' ||
      'dorsales' ||
      'trapecio' =>
        MuscleGroup.espalda,
      'hombros' || 'hombro' || 'cuello' => MuscleGroup.hombros,
      'bíceps' || 'antebrazos' => MuscleGroup.biceps,
      'tríceps' => MuscleGroup.triceps,
      'cuádriceps' || 'aductores' => MuscleGroup.cuadriceps,
      'isquiotibiales' => MuscleGroup.isquiotibiales,
      'glúteos' => MuscleGroup.gluteos,
      'gemelos' || 'pantorrilla' => MuscleGroup.pantorrilla,
      'abdominales' => MuscleGroup.abdominales,
      'cuerpo completo' => MuscleGroup.cuerpoCompleto,
      _ => null,
    };
  }
}

/// Spanish display label for any stored or legacy muscle string. Resolves
/// canonical keys ('chest'→'Pecho') and old Spanish labels alike; returns the
/// raw value unchanged when it doesn't map (so unknown/custom text survives).
///
/// Single source of truth for every read-only surface (exercise detail, the
/// trainer's library, picker row subtitles) so a stored key never leaks to the
/// user as raw English.
String muscleGroupLabel(String? raw) =>
    MuscleGroup.fromKey(raw)?.label ?? (raw ?? '');
