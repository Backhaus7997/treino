// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import '../../../../workout/application/exercise_filter.dart' show foldSearch;
import 'exercise_media_catalog.dart';

/// Resuelve la URL de imagen de demostración de un ejercicio del catálogo,
/// a partir de su nombre (ES o EN).
///
/// Función pura — sin dependencias de Flutter/BuildContext, testeable con
/// `package:test`. Devuelve `null` cuando no hay match confiable (ejercicios
/// CUSTOM, o del catálogo sin media de confianza alta) — el caller debe caer
/// al ícono placeholder, JAMÁS mostrar una imagen equivocada.
///
/// Fuente de datos: [exerciseMediaCatalog] (generado por
/// `scripts/generate_exercise_media_catalog.py` desde
/// `docs/exercises_catalog.json`, solo entradas `has_media == true &&
/// media_confidence == "high"`).
String? exerciseImageUrl(String nombre) {
  final key = _normalizeExerciseKey(nombre);
  if (key.isEmpty) return null;
  return exerciseMediaCatalog[key];
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
  return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
}
