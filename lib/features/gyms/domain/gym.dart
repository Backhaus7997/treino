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

    /// Two-level catalog (marca → sucursal). Cada `Gym` doc es una sucursal;
    /// `brandId` agrupa sucursales de la misma cadena (slug estable derivado
    /// de `brandName`). Para un gym independiente (una sola sucursal),
    /// `brandId` apunta a su propio `id`.
    ///
    /// Nullable para decode backward-compat de los ~20 docs sembrados antes
    /// de esta migración (no tienen estos campos).
    String? brandId,
    String? brandName,

    /// Nombre de la sucursal dentro de la cadena (ej. "Belgrano"). `null`
    /// para gyms independientes (no hay una segunda sucursal de la cual
    /// distinguirse).
    String? branchName,

    /// Opcionales — decode seguro cuando están ausentes en docs viejos.
    String? city,
    String? province,
  }) = _Gym;

  factory Gym.fromJson(Map<String, Object?> json) => _$GymFromJson(json);
}

/// Sentinel id que representa la opción "OTRO GYM / SIN GYM" del mockup.
/// El atleta puede dejarlo sin elegir un gym del catálogo.
///
/// Re-homed desde `profile_setup/domain/gym.dart` (ver ADR gyms-foundation
/// Phase 1) — canonical location ahora vive junto al modelo real de gym.
const String kNoGymId = 'no-gym';
