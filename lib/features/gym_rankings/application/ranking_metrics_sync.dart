import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/domain/user_public_profile.dart';

/// Cuánto esperamos, como máximo, a que la Cloud Function termine de calcular
/// las métricas de ranking después de activar el opt-in.
///
/// La función (`rankingAggregateOnOptIn`) tarda 1-3 s en el caso normal; con un
/// arranque en frío y un historial largo puede pasar de eso. Pasado este plazo
/// dejamos de decir "calculando" y mostramos lo que haya: si el atleta no
/// tiene entrenos, ese 0 ya es la respuesta honesta.
const kRankingMetricsSyncWindow = Duration(seconds: 10);

/// `true` si el doc público de [profile] ya trae ALGUNA métrica de ranking
/// calculada: volumen mayor a cero o algún máximo de levantamiento.
///
/// El modelo hace default a `0` en `lifetimeVolumeKg` cuando el campo falta, y
/// `clearRankingMetrics` lo deja en `0` al desactivar — o sea que el `0` solo
/// no distingue "no entrenó nunca" de "la función todavía no corrió". Esto sí
/// distingue lo único que se puede afirmar: que ya llegó un dato real.
bool hasRankingMetrics(UserPublicProfile? profile) {
  if (profile == null) return false;
  return profile.lifetimeVolumeKg > 0 ||
      profile.bestSquatKg != null ||
      profile.bestBenchKg != null ||
      profile.bestDeadliftKg != null;
}

/// `true` mientras el atleta que acaba de activar los rankings todavía no tiene
/// sus métricas propias calculadas (#1518, AGENTS §11.1).
///
/// Existe porque desde el cliente no hay forma de saber que "la función no
/// corrió todavía": el campo que la función escribe ya viene con un `0` por
/// default, y mostrar ese `0` como volumen real es afirmar un dato que nadie
/// calculó. El flag se enciende SOLO cuando este dispositivo acaba de activar el
/// opt-in; arranca apagado, así que un atleta que ya estaba en los rankings ve
/// sus números como siempre.
///
/// El flag es solo un permiso para decir "calculando": quién lo muestra cruza
/// el flag con [hasRankingMetrics], de modo que apenas llega el dato real la
/// leyenda se va sola, sin esperar al timeout. El timeout (ver
/// [kRankingMetricsSyncWindow]) cubre el caso opuesto: la función corrió pero
/// escribió exactamente lo que ya había (un atleta sin entrenos), que no genera
/// ningún evento nuevo.
class RankingMetricsSync extends Notifier<bool> {
  Timer? _timeout;

  @override
  bool build() {
    ref.onDispose(() => _timeout?.cancel());
    return false;
  }

  /// Llamar apenas el opt-in se escribió OK.
  void start() {
    _timeout?.cancel();
    _timeout = Timer(kRankingMetricsSyncWindow, finish);
    state = true;
  }

  /// Llamar al desactivar los rankings, o cuando se acaba el plazo.
  void finish() {
    _timeout?.cancel();
    _timeout = null;
    if (state) state = false;
  }
}

final rankingMetricsSyncProvider =
    NotifierProvider<RankingMetricsSync, bool>(RankingMetricsSync.new);
