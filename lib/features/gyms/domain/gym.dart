// ignore: unused_import — Timestamp is used by the generated gym.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'gym_source.dart';

part 'gym.freezed.dart';
part 'gym.g.dart';

/// First-class gym entity. Vive en `gyms/{gymId}`.
///
/// Originalmente la app solo tenía `gymId` en `UserProfile` como string
/// libre. Multi-location requiere que el gym sea first-class — cada doc
/// tiene su propia lat/lng + geohash, y los PFs referencian por id.
///
/// Reglas Firestore (deployed in this PR):
///   - read: cualquier user autenticado.
///   - create: PF (role == 'trainer') self-service con `source: self-service`,
///     `createdBy: request.auth.uid`, todos los campos requeridos.
///   - update/delete: denegado client-side. Solo admin via Console o
///     privileged Cloud Function en el futuro.
@freezed
class Gym with _$Gym {
  const factory Gym({
    required String id,
    required String name,
    String? address,
    required double lat,
    required double lng,
    required String geohash,
    required GymSource source,
    String? createdBy,
    @TimestampConverter() required DateTime createdAt,
  }) = _Gym;

  factory Gym.fromJson(Map<String, Object?> json) => _$GymFromJson(json);
}
