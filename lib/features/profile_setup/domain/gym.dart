import 'package:freezed_annotation/freezed_annotation.dart';

part 'gym.freezed.dart';

/// Gym del catálogo que el atleta elige en el step 2 del ProfileSetup.
///
/// Mientras Etapa 3 (Firestore + UserProfile) no esté mergeada, la lista vive
/// hardcoded en `gym_search_provider.dart`. Cuando llegue Firestore, este modelo
/// se hidrata desde la colección `gyms/`.
@freezed
class Gym with _$Gym {
  const factory Gym({
    required String id,
    required String name,
    required String address,
  }) = _Gym;
}

/// Sentinel id que representa la opción "OTRO GYM / SIN GYM" del mockup.
/// El atleta puede dejarlo sin elegir un gym del catálogo.
const String kNoGymId = 'no-gym';
