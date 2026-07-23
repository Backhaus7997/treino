// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import '../../../../workout/application/exercise_filter.dart' show foldSearch;
import 'exercise_media_catalog.dart';

/// Espacios (uno o más) — precompilado a nivel de librería. NUNCA construir
/// un `RegExp` dentro de [exerciseImageUrl] (se llama por card,
/// potencialmente por frame).
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Resuelve la URL de imagen de demostración de un ejercicio del catálogo,
/// a partir de su nombre (ES o EN).
///
/// Función pura — sin dependencias de Flutter/BuildContext, testeable con
/// `package:test`. Devuelve `null` cuando no hay match confiable (ejercicios
/// CUSTOM, o del catálogo sin verificación visual) — el caller debe caer al
/// ícono placeholder, JAMÁS mostrar una imagen equivocada.
///
/// Lookup EXACTO únicamente contra [exerciseMediaCatalog] — NO hay fallback
/// por "nombre base"/variante de equipamiento. Una ronda anterior tuvo ese
/// fallback (bases inequívocas del catálogo), pero una verificación visual
/// imagen-por-imagen (ver `scripts/exercise_media_verified.json`) demostró
/// que variantes de equipamiento (ej. "Curl de Bíceps (Barra)" vs
/// "(Mancuerna)" vs "(Polea)") casi nunca pueden compartir imagen sin
/// mostrar el equipamiento equivocado — se removió el fallback.
///
/// Fuente de datos: [exerciseMediaCatalog] (generado por
/// `scripts/generate_exercise_media_catalog.py` desde
/// `docs/exercises_catalog.json`, filtrado por
/// `scripts/exercise_media_verified.json` — SOLO ejercicios cuya foto fue
/// verificada visualmente como correcta, sin importar `media_confidence`).
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
  return folded.replaceAll(_whitespaceRun, ' ').trim();
}
