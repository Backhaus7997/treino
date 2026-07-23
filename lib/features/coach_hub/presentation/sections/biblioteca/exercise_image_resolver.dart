// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import '../../../../workout/application/exercise_filter.dart' show foldSearch;
import 'exercise_media_catalog.dart';

/// Sufijo de equipamiento: un único grupo `(...)` pegado al final del
/// nombre, con espacio opcional antes (ej. `"Sentadilla (Barra)"`).
/// Precompilado a nivel de librería — NUNCA construir un `RegExp` dentro de
/// [exerciseImageUrl] (se llama por card, potencialmente por frame).
final RegExp _trailingEquipmentSuffix = RegExp(r'\s*\([^)]*\)\s*$');

/// Espacios (uno o más) — también precompilado, mismo motivo.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Resuelve la URL de imagen de demostración de un ejercicio del catálogo,
/// a partir de su nombre (ES o EN).
///
/// Función pura — sin dependencias de Flutter/BuildContext, testeable con
/// `package:test`. Devuelve `null` cuando no hay match confiable (ejercicios
/// CUSTOM, o del catálogo sin media de confianza alta/media) — el caller
/// debe caer al ícono placeholder, JAMÁS mostrar una imagen equivocada.
///
/// Resolución en capas:
/// (a) lookup exacto contra [exerciseMediaCatalog];
/// (b) si el nombre trae un sufijo de equipamiento `(...)`, lookup de la
///     base (nombre sin ese sufijo) contra [exerciseMediaBaseCatalog]
///     (SOLO bases inequívocas — un único ejercicio fuente por base, ver
///     `scripts/generate_exercise_media_catalog.py`);
/// (c) sin match confiable → `null`.
///
/// Fuente de datos: [exerciseMediaCatalog] + [exerciseMediaBaseCatalog]
/// (generados por `scripts/generate_exercise_media_catalog.py` desde
/// `docs/exercises_catalog.json`, solo entradas `has_media == true &&
/// media_confidence` en `{"high", "medium"}`).
String? exerciseImageUrl(String nombre) {
  final key = _normalizeExerciseKey(nombre);
  if (key.isEmpty) return null;

  final exact = exerciseMediaCatalog[key];
  if (exact != null) return exact;

  final withoutEquipment = _stripEquipmentSuffix(nombre);
  if (withoutEquipment == null) return null;
  final baseKey = _normalizeExerciseKey(withoutEquipment);
  if (baseKey.isEmpty) return null;
  return exerciseMediaBaseCatalog[baseKey];
}

/// Normalización de clave — DEBE mantenerse en paridad con `normalize_key`
/// en `scripts/generate_exercise_media_catalog.py`: minúsculas + sin tildes
/// (vía [foldSearch], mismo mapeo de vocales españolas + ñ/ç que usa el
/// buscador de Biblioteca) + espacios colapsados + trim.
///
/// [foldSearch] por sí sola NO colapsa espacios ni trimea — se agrega acá
/// porque el generador Python sí lo hace (nombres del catálogo pueden traer
/// espacios dobles o bordes).
String _normalizeExerciseKey(String input) {
  final folded = foldSearch(input);
  return folded.replaceAll(_whitespaceRun, ' ').trim();
}

/// Remueve un sufijo de equipamiento final `(...)` de [input] — DEBE
/// mantenerse en paridad con `base_key` en
/// `scripts/generate_exercise_media_catalog.py`.
///
/// Devuelve `null` cuando [input] NO trae ese sufijo (nada que remover), así
/// [exerciseImageUrl] sabe cuándo el paso (b) no aplica.
String? _stripEquipmentSuffix(String input) {
  if (!_trailingEquipmentSuffix.hasMatch(input)) return null;
  return input.replaceFirst(_trailingEquipmentSuffix, '');
}
