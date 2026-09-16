// ignore_for_file: invalid_annotation_target — @JsonKey sobre un parámetro
// de factory freezed. json_serializable SÍ lo lee (se ve en session.g.dart);
// el analizador no sabe que freezed lo reenvía. Mismo caso que message.dart.
// ignore: unused_import — Timestamp is used by the generated session.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'exercise_feedback.dart';
import 'feedback_counts_converter.dart';
import 'session_status.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
class Session with _$Session {
  const factory Session({
    required String id,
    required String uid,
    required String routineId,
    required String routineName,
    @TimestampConverter() required DateTime startedAt,
    @TimestampConverter() DateTime? finishedAt,
    @Default(0.0) double totalVolumeKg,
    @Default(0) int durationMin,
    required SessionStatus status,
    @Default(1) int dayNumber,
    @Default(false) bool wasFullyCompleted,
    // Periodization (Model B): 0-based week of the plan this session belongs to.
    // @Default(0) keeps single-week sessions intact and retro-compatible.
    @Default(0) int weekNumber,
    // Cuántos reportes (#628) tiene esta sesión, por kind. Lo escribe SÓLO
    // `maintainSessionFeedbackCounters` (functions/), recontando desde la
    // subcolección; las reglas rechazan que un cliente lo toque.
    //
    // Existe para que el historial del PF marque de un vistazo qué sesiones
    // traen una molestia o una nota. Sin esto la marca cuesta una lectura de
    // subcolección por fila.
    //
    // `@Default({})` y no `required`: las sesiones anteriores al agregado no
    // tienen el campo, y una sesión sin reportes tampoco lo tiene — el mapa
    // vacío es la respuesta correcta para las dos. Ojo con lo que NO significa:
    // vacío es "ningún reporte", no "no se pudo leer".
    //
    // ⚠️ `includeToJson: false` — ESTE CAMPO SE LEE, NO SE ESCRIBE.
    //
    // Sin esto, `SessionRepository.create()` —que es `ref.set(session.toJson())`,
    // el único write de una Session ENTERA— mandaba `feedbackCounts: {}` en
    // cada sesión nueva. Y la regla de Firestore rechaza la clave presente en
    // el `create`, así que el servidor devolvía `permission-denied` y el
    // atleta veía "No pudimos iniciar la sesión": **no se podía empezar a
    // entrenar**.
    //
    // El arreglo correcto no era ablandar la regla para aceptar el mapa vacío,
    // sino que el cliente deje de mandarlo. El campo es del backend: lo escribe
    // sólo `maintainSessionFeedbackCounters` recontando desde
    // `exerciseFeedback`, y que el modelo no pueda emitirlo hace que eso sea
    // cierto por construcción y no por disciplina.
    //
    // Sacarlo del `toJson` es seguro porque `create()` escribe un documento
    // NUEVO: no hay contador que pisar. `finish()` y el barrido usan `update()`
    // con campos explícitos, y los otros `set(x.toJson())` del repositorio son
    // de `SetLog`, no de `Session`.
    @JsonKey(includeToJson: false)
    @FeedbackCountsConverter()
    @Default(<ExerciseFeedbackKind, int>{})
    Map<ExerciseFeedbackKind, int> feedbackCounts,
  }) = _Session;

  factory Session.fromJson(Map<String, Object?> json) =>
      _$SessionFromJson(json);
}

/// Si un documento de sesión cuenta como entrenamiento **HECHO**, a partir de
/// sus valores de wire.
///
/// ⚠️ **Esta función es un contrato compartido con el cliente watchOS**, que la
/// reimplementa en `ios/TreinoWatch Watch App/SessionCounting.swift`. Los
/// fixtures de `conformance/session_counting.json` son la red entre las dos: si
/// una cambia y la otra no, CI se pone en rojo.
///
/// Existe como función suelta —y no solo como el getter de abajo— porque el
/// reloj no deserializa a [Session]: lee el JSON crudo de la REST API de
/// Firestore, donde los campos pueden faltar o venir con nulo explícito. El
/// contrato tiene que estar definido sobre ESO, que es lo que el reloj ve.
///
/// Toma `String?` y no [SessionStatus] a propósito: un valor desconocido tiene
/// que dar `false`, no explotar. La condición es igualdad contra `'finished'`,
/// nunca desigualdad contra `'active'` — si algún día se agrega un estado
/// nuevo, no puede empezar a contar solo.
///
/// `wasFullyCompleted` nulo cuenta como `false`, igual que el `@Default(false)`
/// del modelo: un documento viejo sin la clave no puede empezar a contar de
/// golpe.
bool sessionCountsAsWorkout({
  required String? status,
  required bool? wasFullyCompleted,
}) =>
    status == 'finished' && wasFullyCompleted == true;

extension SessionCounting on Session {
  /// Cuenta como entrenamiento HECHO: terminado de verdad, no abandonado.
  /// Abandonar guarda `status=finished` con `wasFullyCompleted=false`
  /// (ver `SessionNotifier.abandonSession`), así que `status` solo no alcanza.
  ///
  /// Delega en [sessionCountsAsWorkout] en vez de repetir la condición: si se
  /// escribiera acá también, el contrato compartido y el que usa la app
  /// podrían separarse sin que nada se ponga rojo.
  bool get countsAsWorkout => sessionCountsAsWorkout(
        status: status.toJson(),
        wasFullyCompleted: wasFullyCompleted,
      );
}
