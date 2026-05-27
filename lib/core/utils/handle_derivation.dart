/// Derives a social handle from a display name.
///
/// Rule: `displayName.toLowerCase().replaceAll(' ', '.')`.
/// This is a pure function — the handle is NEVER persisted to Firestore.
/// It is derived on every render, so it always matches the current displayName.
///
/// Examples:
/// - "Maria Gomez" → "maria.gomez"
/// - "Ana Núñez" → "ana.núñez"
/// - "Juan Ignacio López" → "juan.ignacio.lópez"
///
/// Returns an empty string when [displayName] is null or empty.
String deriveHandle(String? displayName) {
  if (displayName == null || displayName.trim().isEmpty) return '';
  return displayName.toLowerCase().replaceAll(' ', '.');
}
