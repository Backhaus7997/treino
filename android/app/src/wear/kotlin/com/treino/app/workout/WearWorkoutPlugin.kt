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
     * El temporizador del EJERCICIO POR TIEMPO.
     *
     * Reusa entera la maquinaria del descanso —deadline persistido, defensa
     * contra reboot, alarma exacta con wakelock, vibracion— porque el problema
     * es el mismo: sobrevivir a que se apague la pantalla y avisar al vencer
     * este la app visible o no.
     *
     * Lo que NO comparte es el estado: store y alarma propios. Con uno solo,
     * arrancar un ejercicio por tiempo cancelaria el descanso en curso sin
     * decir nada.
     */
    private val exerciseStore = RestStore(context, RestStore.PREFS_EXERCISE)

    /**
     * El aviso. Separado del store a propósito: el store resuelve "qué número
     * mostrar", la alarma resuelve "cuándo avisar". Son problemas distintos y
     * medido en hardware quedó claro que uno no implica al otro — el descanso
     * llegó a cero con el número correcto y sin que sonara nada.
     */
    private val restAlarm = RestAlarm(context)

    private val exerciseAlarm = RestAlarm(
        context,
        RestAlarm.ALARM_TAG_EXERCISE,
        RestAlarm.WAKELOCK_TAG_EXERCISE,
    )

    /** Idem `deadlineReported`, para el temporizador de ejercicio. */
    private var exerciseDeadlineReported = false

    /** Evita avisar dos veces el mismo vencimiento. */
    private var deadlineReported = false

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

            // Mismo shape que emite Swift (`EffortBroadcastRules.swift`), para
            // que el parser de Dart (`WatchEffort.tryParse`) sea UNO SOLO para
            // las dos plataformas. `measuredAtMs` es obligatorio: sin momento
            // no se puede juzgar la antiguedad, y tryParse descarta el payload.
            "effort" -> {
                val r = ExerciseSessionController.latestReading()
                if (r == null) {
                    result.success(mapOf("nowElapsedMs" to now))
                } else {
                    result.success(
                        buildMap {
                            put("kind", "watchEffort")
                            r.bpm?.let { put("bpm", it) }
                            r.kcal?.let { put("kcal", it) }
                            put("measuredAtMs", r.measuredAtMs)
                            put("nowElapsedMs", now)
                        },
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
                restAlarm.schedule(d, holdWakeLock = call.argument<Boolean>("wakeLock") ?: false)
                deadlineReported = false
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
                    // Camino sin AlarmManager: si el SoC sigue despierto (por el
                    // wakelock), la propia app detecta el vencimiento y avisa.
                    // Una sola vez, la primera.
                    if (d.isFinishedAt(now) && !deadlineReported) {
                        deadlineReported = true
                        restAlarm.onDeadlineNoticedByApp(d.endsAtElapsedMs)
                        // Y se BORRA. Sin esto el descanso vencido queda
                        // persistido para siempre y la capsula no se va nunca:
                        // en el reloj se comia el 23% de la pantalla mostrando
                        // "0s" y empujaba las series abajo del pliegue, asi que
                        // los circulos para marcar no se podian tocar.
                        //
                        // Mismo comportamiento que watchOS, donde `restRemaining`
                        // pasa a nil al terminar y el banner desaparece. El aviso
                        // ya lo dio la vibracion; dejar el cartel no agrega nada.
                        restStore.clear()
                    }
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

            // ── Temporizador del ejercicio por tiempo ────────────────────
            //
            // Mismo contrato que el descanso salvo UNA diferencia, y es
            // deliberada: al vencer NO se borra el deadline. El descanso
            // desaparece solo porque su cartel ya no aporta nada —el aviso lo
            // dio la vibracion— pero acá el atleta tiene que VER que el tiempo
            // termino para recien entonces marcar la serie. Borrarlo haria
            // desaparecer la pantalla justo cuando hay que actuar sobre ella.

            "startExerciseTimer" -> {
                val seconds = call.argument<Int>("seconds") ?: 0
                if (seconds <= 0) {
                    // Mismo criterio que `startRest`: un temporizador de cero
                    // nace vencido y solo ensucia la pantalla.
                    exerciseStore.clear()
                    exerciseAlarm.cancel()
                    result.success(mapOf("ok" to false, "nowElapsedMs" to now))
                } else {
                    val d = RestDeadline.startingAt(now, seconds * 1000L)
                    exerciseStore.save(d)
                    // Wakelock SIEMPRE: un ejercicio por tiempo dura lo que dura
                    // una serie y el atleta no esta mirando el reloj. Sin esto,
                    // Doze difiere la alarma y el aviso llega tarde o no llega.
                    exerciseAlarm.schedule(d, holdWakeLock = true)
                    exerciseDeadlineReported = false
                    result.success(
                        mapOf(
                            "endsAtElapsedMs" to d.endsAtElapsedMs,
                            "totalMs" to d.totalMs,
                            "nowElapsedMs" to now,
                        ),
                    )
                }
            }

            "exerciseTimerState" -> {
                val d = exerciseStore.load(now)
                if (d == null) {
                    result.success(mapOf("nowElapsedMs" to now))
                } else {
                    if (d.isFinishedAt(now) && !exerciseDeadlineReported) {
                        exerciseDeadlineReported = true
                        exerciseAlarm.onDeadlineNoticedByApp(d.endsAtElapsedMs)
                    }
                    result.success(
                        mapOf(
                            "endsAtElapsedMs" to d.endsAtElapsedMs,
                            "totalMs" to d.totalMs,
                            "remainingMs" to d.remainingMsAt(now),
                            "finished" to d.isFinishedAt(now),
                            "nowElapsedMs" to now,
                        ),
                    )
                }
            }

            "cancelExerciseTimer" -> {
                exerciseStore.clear()
                exerciseAlarm.cancel()
                exerciseDeadlineReported = false
                result.success(mapOf("ok" to true, "nowElapsedMs" to now))
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
