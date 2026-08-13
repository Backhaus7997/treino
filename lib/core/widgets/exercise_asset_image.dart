import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cascading bundled-illustration lookup for an exercise, shared by every
/// surface that paints one (detail hero, picker thumbnail, …).
///
/// When [ExerciseAssetImage.thumbnailUrl] is present it becomes step 0 — the
/// real photo of the exercise (a frame of its own video, backfilled by
/// `scripts/extract_exercise_thumbnails.js`) — and the asset cascade below is
/// its network-error fallback.
///
/// Lives in `core/` — not in a feature — because the picker is Coach code and
/// the hero is Workout code; same reasoning as
/// `core/widgets/firebase_storage_video_player.dart`.
///
/// For each id variant (strict, strip-suffix, strip-prefix) it probes BOTH
/// `assets/exercises/` and `assets/muscles/` before falling back to the
/// muscle-group bucket. That lets `assets/muscles/` host movement-pattern
/// assets (e.g. `squat.png` for any squat variant) alongside the strict
/// muscle-group silhouettes (e.g. `quads.png`).
///
/// Order for `exerciseId: 'barbell-back-squat'`, `muscleGroup: 'quads'`:
///   1. `assets/exercises/barbell-back-squat.png`
///   2. `assets/exercises/barbell-back.png`          (strip suffix)
///   3. `assets/exercises/back-squat.png`            (strip prefix)
///   4. `assets/muscles/barbell-back-squat.png`
///   5. `assets/muscles/barbell-back.png`            (strip suffix)
///   6. `assets/muscles/back-squat.png`              (strip prefix)
///   7. `assets/muscles/quads.png`                   (muscle bucket)
///   8. [fallback]
///
/// Single-hyphen ids produce no strip-prefix variant (first == last hyphen):
/// `squat-barbell` probes strict + `squat` only. Deliberate — stripping the
/// prefix of a two-segment id like `bench-press` would probe `press.png`,
/// a nonsense match; the prefix strip exists to drop equipment prefixes on
/// 3+-segment ids.
///
/// Step 7 is what carries the catalogue: the bundled PNGs are named after the
/// pre-#209 ids, so steps 1-6 miss for essentially every imported exercise,
/// while `muscleGroup` is populated for all of them. See
/// `docs/video-catalog-audit/NUEVO-catalogo.json` for the catalogue's real
/// shape (793 exercises, no image field).
///
/// The chain is built once into a list of candidate paths so the rendered
/// widget tree stays flat (one `Image.asset` with a nested `errorBuilder`
/// chain), avoiding rebuilds when the lookup walks down the list.
class ExerciseAssetImage extends StatelessWidget {
  const ExerciseAssetImage({
    super.key,
    required this.exerciseId,
    required this.muscleGroup,
    required this.fallback,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String exerciseId;
  final String muscleGroup;

  /// Foto real del ejercicio (frame de su video, 256px, escrita por
  /// `scripts/extract_exercise_thumbnails.js`). Cuando está presente es el
  /// nivel 0 de la cascada; si la red falla o el campo es null se sigue con
  /// los assets locales de siempre. La lista y el detalle comparten este
  /// widget, así que ambos degradan idéntico.
  final String? thumbnailUrl;

  /// Painted when every candidate misses — callers pick what "no illustration"
  /// looks like on their surface (gradient on the hero, icon on a thumbnail).
  final Widget fallback;

  final double? width;
  final double? height;
  final BoxFit fit;

  Widget _tryAt(int index, List<String> paths) {
    if (index >= paths.length) return fallback;
    return Image.asset(
      paths[index],
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _tryAt(index + 1, paths),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paths = exerciseAssetCandidates(
      exerciseId: exerciseId,
      muscleGroup: muscleGroup,
    );
    final url = thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        // Los thumbs viven en Storage a 256px nativos — decodificar más
        // grande solo quema memoria (guideline del PR template).
        memCacheWidth: 256,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, __) => SizedBox(width: width, height: height),
        errorWidget: (_, __, ___) => _tryAt(0, paths),
      );
    }
    return _tryAt(0, paths);
  }
}

/// The id-derived slugs to probe in priority order: strict, strip-suffix,
/// strip-prefix. Skips duplicates and returns empty for a blank id.
List<String> _idSlugs(String exerciseId) {
  if (exerciseId.isEmpty) return const [];
  final out = <String>[exerciseId];
  final last = exerciseId.lastIndexOf('-');
  if (last > 0) out.add(exerciseId.substring(0, last));
  final first = exerciseId.indexOf('-');
  if (first > 0 && first != last) out.add(exerciseId.substring(first + 1));
  return out;
}

/// All candidate asset paths in priority order — see [ExerciseAssetImage].
///
/// Top-level + pure so the ordering can be pinned in unit tests without
/// mounting a widget or shipping fixture PNGs.
List<String> exerciseAssetCandidates({
  required String exerciseId,
  required String muscleGroup,
}) {
  final slugs = _idSlugs(exerciseId);
  final out = <String>[
    for (final s in slugs) 'assets/exercises/$s.png',
    for (final s in slugs) 'assets/muscles/$s.png',
  ];
  if (muscleGroup.isNotEmpty) {
    out.add('assets/muscles/$muscleGroup.png');
  }
  return out;
}
