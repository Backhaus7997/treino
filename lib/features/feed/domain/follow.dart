// ignore: unused_import — Timestamp is used by the generated follow.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'follow_status.dart';

part 'follow.freezed.dart';
part 'follow.g.dart';

/// Una arista DIRIGIDA del grafo social: [followerUid] sigue a [followeeUid].
///
/// Reemplaza a `Friendship`, que era un documento por PAR con acceso simétrico
/// — ahí "A sigue a B pero B no a A" era imposible de representar, y por eso
/// "seguidores" y "seguidos" terminaban siendo el mismo conjunto de gente.
///
/// La diferencia estructural con `Friendship` está en el id: [edgeId] NO
/// ordena los uids. Si los ordenara, las dos direcciones colisionarían en el
/// mismo documento y volveríamos al problema original.
///
/// [members] es redundante con `followerUid`/`followeeUid` y existe para una
/// sola cosa: poder resolver "todas las aristas que tocan a este usuario" con
/// un `array-contains` en vez de dos queries. La DIRECCIÓN nunca se lee de
/// `members` —el orden dentro del array no es contrato de acceso—, se lee de
/// los dos campos dedicados.
@freezed
class Follow with _$Follow {
  const Follow._();

  const factory Follow({
    required String id,
    required String followerUid,
    required String followeeUid,
    required FollowStatus status,
    required List<String> members,
    @TimestampConverter() required DateTime createdAt,
  }) = _Follow;

  factory Follow.fromJson(Map<String, Object?> json) => _$FollowFromJson(json);

  /// Doc id de la arista: `'{follower}_{followee}'`, **sin ordenar**.
  ///
  /// Que el id sea determinístico a partir de la dirección es lo que permite
  /// que las rules resuelvan "¿el lector sigue al autor?" con un lookup
  /// directo por doc id, sin queries y sin índices.
  static String edgeId(String followerUid, String followeeUid) =>
      '${followerUid}_$followeeUid';
}
