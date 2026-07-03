/// A distance-ranked gym result from Google Places `searchNearby` (New).
///
/// Mapped from `places[]` in the response — see [PlacesNearbySearchService].
/// Plain DTO (NOT freezed, mirrors [GymSuggestion]'s style) — lives only in
/// memory during a screen-open, never persisted or serialized to Firestore.
///
/// Distinct from [GymSuggestion] per design gym-selection-v2 AD-8:
/// `searchNearby` results carry `lat`/`lng` (needed for client-side
/// haversine "a X km" labels, AD-6), which Autocomplete predictions never
/// have. Keeping a dedicated DTO avoids polluting [GymSuggestion] with
/// fields that would always be null on the Autocomplete path.
class NearbyGym {
  const NearbyGym({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  /// Google Place ID — same namespace as [GymSuggestion.placeId], feeds the
  /// identical `select(uid, placeId)` resolution path.
  final String placeId;

  /// `displayName.text`.
  final String name;

  /// `formattedAddress`. Some results omit it.
  final String? address;

  /// `location.latitude` — required (searchNearby always returns location
  /// when `places.location` is in the field mask, AD-6).
  final double lat;

  /// `location.longitude`.
  final double lng;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NearbyGym &&
          other.placeId == placeId &&
          other.name == name &&
          other.address == address &&
          other.lat == lat &&
          other.lng == lng);

  @override
  int get hashCode => Object.hash(placeId, name, address, lat, lng);

  @override
  String toString() =>
      'NearbyGym(placeId: $placeId, name: $name, address: $address, '
      'lat: $lat, lng: $lng)';
}
