// ignore: unused_import — Timestamp is used by the generated check_in.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import '../../workout/domain/muscle_group.dart';

part 'check_in.freezed.dart';
part 'check_in.g.dart';

/// Cómo se sintió el usuario. Escala CORTA de 5 niveles con emoji — nunca
/// numérica.
///
/// La escala numérica tipo EVA clínica (0-10) quedó descartada a propósito:
/// acerca el producto al terreno médico y es más difícil de responder honesta
/// y rápidamente. Para ver una TENDENCIA ("me duele menos que el mes pasado")
/// alcanza y sobra con 5 niveles.
///
/// [wire] es el valor que se persiste en Firestore — estable e independiente
/// del nombre del símbolo Dart, así renombrar el enum no migra datos.
enum CheckInFeeling {
  @JsonValue('very_bad')
  muyMal('very_bad', '😞'),
  @JsonValue('bad')
  mal('bad', '😕'),
  @JsonValue('neutral')
  normal('neutral', '😐'),
  @JsonValue('good')
  bien('good', '🙂'),
  @JsonValue('great')
  muyBien('great', '😄');

  const CheckInFeeling(this.wire, this.emoji);

  /// Valor persistido en Firestore.
  final String wire;

  /// Glifo de la escala. La etiqueta de texto NO vive acá: es l10n.
  final String emoji;

  /// Orden canónico de peor a mejor — el mismo que usa la fila de la UI.
  static const List<CheckInFeeling> displayOrder = CheckInFeeling.values;

  /// Resuelve un valor persistido a su nivel. `null` si no mapea (dato viejo
  /// o corrupto) — el caller decide si descarta el doc.
  static CheckInFeeling? fromWire(String? raw) {
    if (raw == null) return null;
    for (final f in CheckInFeeling.values) {
      if (f.wire == raw) return f;
    }
    return null;
  }
}

/// Persiste las zonas de dolor como las CLAVES canónicas de [MuscleGroup]
/// (`chest`, `back`, `quads`…), no como nombres de símbolos Dart.
///
/// Es la razón de existir de este converter: el default de json_serializable
/// serializaría por nombre de enum (`pecho`, `espalda`) y eso rompería el
/// vocabulario único que ya comparten el catálogo, los custom exercises, el
/// filtro del picker y el rollup de Insights.
///
/// La lectura pasa por [MuscleGroup.fromKey], así que también canonicaliza
/// las etiquetas en español legacy y DESCARTA lo que no mapea — un valor
/// desconocido no rompe el doc entero.
class MuscleGroupKeysConverter
    implements JsonConverter<List<MuscleGroup>, List<Object?>> {
  const MuscleGroupKeysConverter();

  @override
  List<MuscleGroup> fromJson(List<Object?> json) => json
      .whereType<String>()
      .map(MuscleGroup.fromKey)
      .whereType<MuscleGroup>()
      .toList(growable: false);

  @override
  List<Object?> toJson(List<MuscleGroup> object) =>
      object.map((g) => g.key).toList(growable: false);
}

/// Largo máximo de la nota libre. Corto a propósito: es un apunte, no un
/// diario. El campo `notes` de `Measurement` (2000) es otra cosa.
const int kCheckInNoteMaxLength = 500;

/// Zonas que se ofrecen para el dolor: la taxonomía de [MuscleGroup] MENOS
/// `cardio`, que es una modalidad de entrenamiento y no una parte del cuerpo.
///
/// Vive en el dominio y no en la pantalla para que el check-in diario ofrezca
/// exactamente la misma lista: dos filtros duplicados en dos UIs es
/// exactamente cómo una taxonomía única empieza a divergir.
final List<MuscleGroup> kCheckInPainAreas = List.unmodifiable(
  MuscleGroup.displayOrder.where((g) => g != MuscleGroup.cardio),
);

/// Registro subjetivo de UN día: cómo se sintió el usuario y si tuvo dolor.
///
/// Vive en `users/{uid}/checkIns/{date}` — subcolección propia, NO campos
/// colgados de `Session`. Colgarlo de la sesión arrastraría los `hasOnly` de
/// `firestore.rules` (#635) y además dejaría sin registro los días que el
/// usuario no entrena, que son la mayoría.
///
/// **[date] es el id del documento**: la fecha LOCAL del usuario en formato
/// `YYYY-MM-DD` (ver [checkInDateKey]). Eso da dedup natural — un doc por día
/// por usuario — y es lo que ya documentan las reglas de Firestore. La
/// contracara: dos check-ins el mismo día se pisan (last write wins).
///
/// ⚠️ La app REGISTRA lo que el usuario reporta; no interpreta, no
/// diagnostica y no recomienda. Ningún consumidor de este modelo puede
/// derivar consejo de salud a partir de estos campos.
@freezed
class CheckIn with _$CheckIn {
  const factory CheckIn({
    /// Fecha local `YYYY-MM-DD`. Es también el id del documento.
    required String date,

    /// Cómo se sintió. Único campo obligatorio del registro.
    required CheckInFeeling feeling,

    /// Si reportó dolor o molestia. Se guarda aparte de [painAreas] porque
    /// "me duele pero no sé bien dónde" es una respuesta válida y distinta de
    /// "no me duele".
    @Default(false) bool hasPain,

    /// Zonas del dolor, en el vocabulario de [MuscleGroup]. Vacío cuando
    /// [hasPain] es `false` o cuando el usuario no precisó la zona.
    @Default(<MuscleGroup>[])
    @MuscleGroupKeysConverter()
    List<MuscleGroup> painAreas,

    /// Nota libre opcional, hasta [kCheckInNoteMaxLength] caracteres.
    /// Complementa el dato estructurado; no lo reemplaza (el texto libre no
    /// se agrega y sin agregación no hay curva).
    String? note,

    /// Cuándo se registró, en UTC. [date] es la fecha LOCAL: cerca de
    /// medianoche los dos pueden caer en días distintos, y eso es correcto —
    /// el usuario piensa en su día, no en el de UTC.
    @TimestampConverter() required DateTime recordedAt,

    /// Sesión que originó el registro, cuando se capturó al terminar de
    /// entrenar. `null` para un check-in que no salió de una sesión.
    String? sessionId,
  }) = _CheckIn;

  factory CheckIn.fromJson(Map<String, Object?> json) =>
      _$CheckInFromJson(json);
}

/// Clave de fecha LOCAL `YYYY-MM-DD` usada como id del documento.
///
/// Deliberadamente local y no UTC: el usuario que entrena a las 22:00 en
/// Córdoba (UTC-3) espera que su registro cuente para HOY, no para mañana.
String checkInDateKey(DateTime local) {
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
