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
@freezed
class Block with _$Block {
  const Block._();

  const factory Block({
    required String id,
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
