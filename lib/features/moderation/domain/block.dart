// ignore: unused_import — Timestamp is used by the generated block.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'block.freezed.dart';
part 'block.g.dart';

/// Una arista DIRIGIDA: [blockerUid] bloqueó a [blockedUid].
///
/// Copia el molde de `Follow` (`features/feed/domain/follow.dart`): id
/// compuesto SIN ordenar —si se ordenara, las dos direcciones colisionarían
/// en el mismo documento— y [members] redundante con los dos campos
/// dedicados, sólo para poder resolver "todas las aristas que tocan a este
/// usuario" con un `array-contains` sin doble query.
///
/// A diferencia de `Follow`, no hay `pending → accepted`: bloquear no se
/// negocia, así que no hay un `status`. Ver `openspec/changes/
/// moderacion-reporte-y-bloqueo/design.md`.
///
/// ⚠️ [id] lleva `includeToJson: false` — a propósito NO como `Follow`, cuya
/// regla de `create` sí incluye `'id'` en su `hasOnly` y lo valida contra el
/// doc id (`firestore.rules:1921-1924`). La regla de `blocks`
/// (`firestore.rules:4226-4229`) hace `hasOnly(['blockerUid', 'blockedUid',
/// 'members', 'createdAt'])` — CUATRO campos, sin `id`. Si `toJson()`
/// incluyera `id` el `create` se rechazaría con `PERMISSION_DENIED` porque
/// sobra una key. `id` se sigue synthetizando al LEER, igual que `Follow`
/// (`_fromDoc` inyecta `snap.id`).
@freezed
class Block with _$Block {
  const Block._();

  const factory Block({
    // ignore: invalid_annotation_target — falso positivo de freezed, ver dartdoc de clase.
    @JsonKey(includeToJson: false) required String id,
    required String blockerUid,
    required String blockedUid,
    required List<String> members,
    @TimestampConverter() required DateTime createdAt,
  }) = _Block;

  factory Block.fromJson(Map<String, Object?> json) => _$BlockFromJson(json);

  /// Doc id de la arista: `'{blocker}_{blocked}'`, **sin ordenar**.
  static String edgeId(String blockerUid, String blockedUid) =>
      '${blockerUid}_$blockedUid';
}
