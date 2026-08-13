package com.treino.app.workout

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Puente Dart ↔ Android para la supervivencia del entreno.
 *
 * ## Las dos reglas del contrato
 *
 * 1. **El nativo emite DEADLINES, nunca cuentas regresivas.** Dart jamás recibe
 *    "quedan 42 s": recibe "el descanso termina en el instante X". Así, cuántas
 *    veces corrió el timer de Dart deja de importar — un descanso donde la app
 *    no ejecutó un solo tick muestra igual el número correcto al volver.
 * 2. **Todo lo que se devuelve trae `nowElapsedMs`**, para que Dart pueda restar
 *    sin pagar un segundo cruce de platform channel (que además introduciría su
 *    propia latencia entre las dos lecturas).
 *
 * `elapsedRealtime()` es el único reloj que sirve de fuente de verdad: es
 * monotónico Y sobrevive a la suspensión. El `Stopwatch` de Dart es
 * `clock_gettime(CLOCK_MONOTONIC)`, que se CONGELA con el sistema suspendido, y
 * `DateTime.now()` es wall clock, que salta cuando el teléfono le sincroniza la
 * hora al reloj. Ninguno de los dos sirve, y por eso este canal existe.
 */
class WearWorkoutPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "com.treino.app/wear_workout/methods"
    }

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(::onCall)
    }

    /**
     * Descanso en curso. Vive en el nativo porque tiene que sobrevivir al engine,
     * y PERSISTIDO porque tiene que sobrevivir al proceso — que en Android muere
     * sin aviso por los power managers de los OEM.
     */
    private val restStore = RestStore(context)

    /**
     * El aviso. Separado del store a propósito: el store resuelve "qué número
     * mostrar", la alarma resuelve "cuándo avisar". Son problemas distintos y
     * medido en hardware quedó claro que uno no implica al otro — el descanso
     * llegó a cero con el número correcto y sin que sonara nada.
     */
    private val restAlarm = RestAlarm(context)

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        val now = SystemClock.elapsedRealtime()
        when (call.method) {
            // Los tres relojes de una sola vez, leídos lo más juntos posible.
            // Sirven para distinguir suspensión real (boot avanza, mono no) de
            // proceso despierto pero hambreado (los dos avanzan, faltan
            // callbacks). Sin esta discriminación, "el timer se murió" no dice
            // por qué, y el arreglo de una causa no sirve para la otra.
            "clocks" -> result.success(
                mapOf(
                    "bootMs" to now,                          // CLOCK_BOOTTIME
                    "uptimeMs" to SystemClock.uptimeMillis(), // CLOCK_MONOTONIC
                    "wallMs" to System.currentTimeMillis(),
                ),
            )

            "startForegroundService" -> {
                val withOngoing = call.argument<Boolean>("withOngoing") ?: true
                val intent = Intent(context, WorkoutForegroundService::class.java).apply {
                    action = WorkoutForegroundService.ACTION_START
                    putExtra(WorkoutForegroundService.EXTRA_WITH_ONGOING, withOngoing)
                    putExtra(WorkoutForegroundService.EXTRA_STARTED_AT_ELAPSED, now)
                }
                try {
                    // `startForegroundService` devuelve null —y NO tira— cuando
                    // el componente no está declarado en el manifest mergeado.
                    // Sin este chequeo el keep-alive degrada en silencio al
                    // comportamiento SIN servicio, y la medición diría "ok"
                    // mientras la app se muere. Es exactamente el modo de falla
                    // que hay hoy: el <service> vive en src/debug/, así que en
                    // release ni se declara.
                    val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    if (started == null) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "error" to "servicio NO declarado en el manifest de este build " +
                                    "(el <service> solo esta en src/debug/)",
                                "nowElapsedMs" to now,
                            ),
                        )
                    } else {
                        result.success(mapOf("ok" to true, "nowElapsedMs" to now))
                    }
                } catch (e: Exception) {
                    // Se devuelve en vez de tirar: el spike necesita MEDIR el
                    // fallo, no morirse. El caso típico es la precondición de
                    // runtime del tipo `health` sin cumplir.
                    result.success(
                        mapOf(
                            "ok" to false,
                            "error" to "${e.javaClass.simpleName}: ${e.message}",
                            "nowElapsedMs" to now,
                        ),
                    )
                }
            }

            "stopForegroundService" -> {
                context.startService(
                    Intent(context, WorkoutForegroundService::class.java)
                        .apply { action = WorkoutForegroundService.ACTION_STOP },
                )
                result.success(mapOf("ok" to true, "nowElapsedMs" to now))
            }

            "startRest" -> {
                val seconds = call.argument<Int>("seconds") ?: 0
                val d = RestDeadline.startingAt(now, seconds * 1000L)
                restStore.save(d)
                restAlarm.schedule(d)
                result.success(
                    mapOf(
                        "restEndsAtElapsedMs" to d.endsAtElapsedMs,
                        "nowElapsedMs" to now,
                    ),
                )
            }

            // Se lee del STORE, no de un campo: así el descanso sobrevive a que
            // el proceso muera. Es lo único que distingue este diseño de un
            // contador de ticks — si alcanzara con mantener vivo el proceso, el
            // deadline sería ceremonia. `load` ya descarta por reboot y borra la
            // basura, así que acá no hay que chequear nada más.
            "restState" -> {
                val d = restStore.load(now)
                if (d == null) {
                    result.success(mapOf("nowElapsedMs" to now))
                } else {
                    result.success(
                        mapOf(
                            "restEndsAtElapsedMs" to d.endsAtElapsedMs,
                            "remainingMs" to d.remainingMsAt(now),
                            "finished" to d.isFinishedAt(now),
                            "nowElapsedMs" to now,
                        ),
                    )
                }
            }

            "cancelRest" -> {
                restStore.clear()
                restAlarm.cancel()
                result.success(mapOf("ok" to true, "nowElapsedMs" to now))
            }

            else -> result.notImplemented()
        }
    }
}
