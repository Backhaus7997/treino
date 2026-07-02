/// Sugerencia de gym de una respuesta de Google Places Autocomplete (New).
///
/// Mapeada desde `suggestions[].placePrediction` — ver
/// `PlacesAutocompleteService`. Plain DTO (NOT freezed, per design
/// gym-google-places #348) — vive solo en memoria durante una sesión de
/// búsqueda, nunca se persiste ni serializa a Firestore.
class GymSuggestion {
  const GymSuggestion({
    required this.placeId,
    required this.primaryText,
    this.secondaryText,
  });

  /// Google Place ID — se usa directamente como `gymId` al resolver
  /// (`resolveGymPlace` CF upsert de `gyms/{placeId}`).
  final String placeId;

  /// `structuredFormat.mainText.text` — típicamente el nombre del lugar.
  final String primaryText;

  /// `structuredFormat.secondaryText.text` — típicamente la dirección.
  /// Algunas predicciones no la incluyen.
  final String? secondaryText;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GymSuggestion &&
          other.placeId == placeId &&
          other.primaryText == primaryText &&
          other.secondaryText == secondaryText);

  @override
  int get hashCode => Object.hash(placeId, primaryText, secondaryText);

  @override
  String toString() =>
      'GymSuggestion(placeId: $placeId, primaryText: $primaryText, '
      'secondaryText: $secondaryText)';
}
