// ignore: unused_import — Timestamp is used by the generated
// verified_email.g.dart part.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../data/timestamp_converter.dart';

part 'verified_email.freezed.dart';
part 'verified_email.g.dart';

/// Una entrada de `users/{uid}.emailVerification.<rol>`: qué mail confirmó la
/// cuenta con el código de 6 dígitos, y cuándo. Ver
/// `functions/src/auth/codigo-de-verificacion.ts`.
///
/// Solo lectura: la escribe la Cloud Function `verificarCodigoDeMail`. Quién
/// decide si alcanza para pasar el gate es `correoVerificadoParaElRol`.
@freezed
class VerifiedEmail with _$VerifiedEmail {
  const factory VerifiedEmail({
    // `''` y no `required`: tolera una entrada a la que le FALTA `email` (el
    // gate la lee como "no verificado"). Nada más: una entrada null o que no sea
    // un mapa, o un `verifiedAt` que no sea Timestamp, siguen tirando en
    // `fromJson` y el perfil entero no parsea. Como este mapa lo escribe solo la
    // Cloud Function, una forma rota solo vendría de una operación manual con el
    // Admin SDK.
    @Default('') String email,
    @TimestampConverter() DateTime? verifiedAt,
  }) = _VerifiedEmail;

  factory VerifiedEmail.fromJson(Map<String, Object?> json) =>
      _$VerifiedEmailFromJson(json);
}
