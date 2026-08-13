/// Single source of truth for composing a separator-joined line.
///
/// Every surface that builds "A · B · C" has the same latent defect: the
/// moment one segment resolves to empty — an unmapped muscle group, a routine
/// with no split, a slot with no name — a plain `join` or a string
/// interpolation leaks a dangling separator (" · Otro", " · DÍA 1").
///
/// [joinNonEmpty] drops the empty segments BEFORE joining, so a separator only
/// ever sits between two pieces that actually have content. A missing piece
/// degrades to a shorter line instead of a stray "·".
library;

/// Joins [parts] with [separator], discarding `null` and blank segments first.
///
/// Blank means empty or whitespace-only — a "   " segment renders as a dangling
/// separator just the same. Retained segments are passed through untouched:
/// filtering is this helper's job, formatting stays with the caller.
///
/// ```dart
/// joinNonEmpty(['', 'Otro', 'Abdominales'], ' · '); // 'Otro · Abdominales'
/// joinNonEmpty(['', 'DÍA 1'], ' · ');               // 'DÍA 1'
/// joinNonEmpty(['PPL', 'DÍA 1'], ' · ');            // 'PPL · DÍA 1'
/// ```
String joinNonEmpty(Iterable<String?> parts, String separator) => parts
    .whereType<String>()
    .where((part) => part.trim().isNotEmpty)
    .join(separator);
