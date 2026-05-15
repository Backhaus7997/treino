import '../../profile_setup/domain/gym.dart' show kNoGymId;

/// Hardcoded gym display name lookup. Parallel to `_kHardcodedGyms` in
/// `profile_setup_providers.dart` (private). Both maps stay in lockstep until
/// a `gyms` Firestore collection replaces them (Fase 4+).
const Map<String, String> _kGymNames = {
  'smart-fit-palermo': 'SMART FIT',
  'sportclub-belgrano': 'SPORTCLUB',
  'megatlon-recoleta': 'MEGATLON',
};

/// Resolves a gym id to a display name for UI rendering.
///
/// - `null`, `''`, or [kNoGymId] sentinel → empty string (caller hides subtitle)
/// - known id → mapped display name
/// - unknown id → `id.toUpperCase()` best-effort fallback (visible signal that
///   the catalog is stale)
String gymNameFromId(String? gymId) {
  if (gymId == null || gymId.isEmpty || gymId == kNoGymId) return '';
  return _kGymNames[gymId] ?? gymId.toUpperCase();
}
