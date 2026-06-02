/// Equipment type for catalog and custom exercises.
///
/// Used by the exercise picker filter sheet (PR2) and backfill script (PR1).
/// JSON wire format is snake_case (see [jsonValue]). Unknown or missing values
/// deserialize to null — filter logic treats null as "match all".
enum EquipmentType {
  mancuerna,
  barra,
  maquina,
  cable,
  banda, // resistance bands — covers home + gym
  pesoCorporal, // bodyweight — pull-ups, dips, planks, hanging leg raise
  cardio, // treadmill, bike, rower — reserved for future fase
  otro, // any equipment the catalog does not recognize
  ninguno; // explicit "no equipment" — stretching / mobility

  String get label => switch (this) {
        EquipmentType.mancuerna => 'Mancuerna',
        EquipmentType.barra => 'Barra',
        EquipmentType.maquina => 'Máquina',
        EquipmentType.cable => 'Cable',
        EquipmentType.banda => 'Banda',
        EquipmentType.pesoCorporal => 'Peso corporal',
        EquipmentType.cardio => 'Cardio',
        EquipmentType.otro => 'Otro',
        EquipmentType.ninguno => 'Ninguno',
      };

  /// snake_case wire format — must match the seed/backfill JS exactly.
  String get jsonValue => switch (this) {
        EquipmentType.mancuerna => 'mancuerna',
        EquipmentType.barra => 'barra',
        EquipmentType.maquina => 'maquina',
        EquipmentType.cable => 'cable',
        EquipmentType.banda => 'banda',
        EquipmentType.pesoCorporal => 'peso_corporal',
        EquipmentType.cardio => 'cardio',
        EquipmentType.otro => 'otro',
        EquipmentType.ninguno => 'ninguno',
      };

  static EquipmentType? fromJson(String? raw) {
    if (raw == null) return null;
    return switch (raw) {
      'mancuerna' => EquipmentType.mancuerna,
      'barra' => EquipmentType.barra,
      'maquina' => EquipmentType.maquina,
      'cable' => EquipmentType.cable,
      'banda' => EquipmentType.banda,
      'peso_corporal' => EquipmentType.pesoCorporal,
      'cardio' => EquipmentType.cardio,
      'otro' => EquipmentType.otro,
      'ninguno' => EquipmentType.ninguno,
      _ => null, // unknown wire string → null (filter matches all)
    };
  }
}
