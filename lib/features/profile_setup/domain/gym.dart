import 'package:freezed_annotation/freezed_annotation.dart';

part 'gym.freezed.dart';

/// LEGACY — gym hardcodeado usado únicamente por `_kHardcodedGyms` en
/// `profile_setup_providers.dart`. Reemplazado por `gyms/domain/gym.dart`
/// (catálogo real, two-level brand→sucursal). Este modelo y sus dos únicos
/// consumidores (`filteredGymsProvider`, `_kHardcodedGyms`) se eliminan en
/// gyms-foundation Phase 2, junto con el picker que los usa.
///
/// `kNoGymId` fue re-homed a `gyms/domain/gym.dart` — no vive más acá.
@freezed
class Gym with _$Gym {
  const factory Gym({
    required String id,
    required String name,
    required String address,
  }) = _Gym;
}
