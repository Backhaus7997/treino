package com.treino.app.workout

import android.content.Context
import android.util.Log
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.data.WarmUpConfig
import androidx.health.services.client.endExercise
import androidx.health.services.client.getCurrentExerciseInfo
import androidx.health.services.client.prepareExercise
import androidx.health.services.client.startExercise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/// Última lectura de esfuerzo, para que la lea el platform channel.
///
/// Se llena desde el ejercicio y se lee desde el plugin. `@Volatile` porque los
/// callbacks de Health Services llegan en otro hilo que el de la lectura.
data class EffortReading(
    val bpm: Int?,
    val kcal: Int?,
    /// Wall clock en ms, que es lo que `WatchEffort.tryParse` espera en
    /// `measuredAtMs`. Sin este campo el parser de Dart descarta el payload
    /// entero: sin momento no se puede juzgar la antigüedad.
    val measuredAtMs: Long,
)

/**
 * Envoltura de `ExerciseClient` de Health Services.
 *
 * Es la ÚNICA clase que toca `androidx.health`. El resto del código habla con
 * [EffortReading], así que cambiar de API toca un solo archivo.
 *
 * ## Qué aporta y qué NO
 *
 * Aporta los DATOS: `HEART_RATE_BPM` y `CALORIES`. El tracking corre en el MCU
 * —"the low-power processor responsible for exercise tracking"— fuera de nuestro
 * proceso.
 *
 * **NO mantiene vivo nada.** La propia doc de Google te manda a hacerlo aparte:
 * *"Use a continuously running ForegroundService in conjunction with
 * ExerciseClient to help ensure correct operation for the entire workout."*
 * Medido en este proyecto: sin el foreground service la app cubre el 22.6% del
 * tiempo despierto; con él, el 100.0%. Son mitades COMPLEMENTARIAS, no
 * redundantes — y ésa es la asimetría con watchOS, donde las dos hacían lo
 * mismo y ninguna alcanzaba sola.
 *
 * ## Singleton, y el guard va acá adentro
 *
 * El reloj entra en modo entreno por varios caminos, y al arrancar la app más de
 * uno puede correr en paralelo. Un `if (session == null)` en cada llamador NO
 * alcanza: la carrera pasa antes de que ninguno asigne. Por eso el guard es
 * `@Synchronized` sobre el recurso, no sobre los llamadores. Es la lección
 * literal del ciclo de watchOS.
 */
object ExerciseSessionController {

    private const val TAG = "TreinoExercise"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private var client: ExerciseClient? = null
    private var started = false

    @Volatile
    private var latest: EffortReading? = null

    /** Calorías acumuladas del entreno. Se guardan porque llegan como total. */
    @Volatile
    private var kcalAccumulated: Int? = null

    fun latestReading(): EffortReading? = latest

    private val callback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            // `isEnded`, NUNCA `state == ExerciseState.ENDED`. Los estados
            // legacy (TERMINATED, AUTO_ENDED, ...) los siguen emitiendo
            // versiones viejas del APK de Health Services y son `internal`, así
            // que ni se pueden comparar. Preguntar por ENDED es un bug latente
            // que se manifiesta como "el entreno nunca termina" en relojes
            // viejos.
            if (update.exerciseStateInfo.state.isEnded) {
                Log.i(TAG, "ejercicio terminado: ${update.exerciseStateInfo}")
                started = false
                return
            }

            val bpm = update.latestMetrics
                .getData(DataType.HEART_RATE_BPM)
                .lastOrNull()
                ?.value
                ?.toInt()

            val kcal = update.latestMetrics
                .getData(DataType.CALORIES_TOTAL)
                ?.total
                ?.toInt()
            if (kcal != null) kcalAccumulated = kcal

            // Un bpm de 0 no es una medición: es un sensor que no enganchó. Se
            // descarta acá para que Dart no tenga que saberlo — aunque
            // `WatchEffort.tryParse` también lo filtra, por si acaso.
            latest = EffortReading(
                bpm = bpm?.takeIf { it > 0 },
                kcal = kcalAccumulated,
                measuredAtMs = System.currentTimeMillis(),
            )
        }

        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
            Log.i(TAG, "disponibilidad $dataType -> $availability")
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit

        override fun onRegistered() {
            Log.i(TAG, "callback registrado")
        }

        override fun onRegistrationFailed(throwable: Throwable) {
            Log.w(TAG, "fallo el registro del callback", throwable)
        }
    }

    /**
     * Arranca el ejercicio, o se re-engancha a uno que ya estaba.
     *
     * Se llama DESDE EL SERVICIO, no desde la Activity: la doc avisa que *"if it
     * is not in a service and is tied to the activity lifecycle, then the sensor
     * preparation might be unnecessarily killed"*.
     */
    @Synchronized
    fun start(context: Context) {
        if (started) {
            Log.i(TAG, "ya estaba arrancado, no se arranca de nuevo")
            return
        }
        started = true

        // El contador arranca de CERO en cada entreno.
        //
        // `CALORIES_TOTAL` de Health Services es acumulado DEL EJERCICIO, y
        // `kcalAccumulated` sobrevive mientras viva el proceso — este objeto es
        // un singleton. Sin este reseteo, abandonar y volver a empezar mostraba
        // el total del entreno anterior: el dueño lo vio en 915 kcal recién
        // arrancado.
        latest = null
        kcalAccumulated = null

        val exerciseClient = HealthServices.getClient(context).exerciseClient
        client = exerciseClient

        scope.launch {
            try {
                // SIEMPRE preguntar primero. Si ya hay un ejercicio nuestro en
                // curso hay que RE-REGISTRAR el callback, no arrancar otro: en
                // todo el dispositivo hay UN solo ejercicio activo, y arrancar
                // encima del de otra app se la pisa sin avisarle al atleta.
                val info = exerciseClient.getCurrentExerciseInfo()
                Log.i(TAG, "estado actual: ${info.exerciseTrackedStatus}")

                // Y si el nuestro TODAVÍA está en curso, se cierra ANTES de
                // arrancar el nuevo. Ésta es la otra mitad del bug: `stop()`
                // lanza `endExercise()` en una corrutina y vuelve enseguida, así
                // que abandonar y volver a empezar rápido arrancaba encima de un
                // ejercicio que se estaba cerrando. Health Services seguía
                // contando el mismo, y las calorías del entreno nuevo nacían con
                // el total del viejo.
                //
                // Se hace acá y no en `stop()` porque acá se puede ESPERAR: es
                // la corrutina que necesita el estado limpio.
                if (info.exerciseTrackedStatus == ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS) {
                    Log.i(TAG, "habia un ejercicio nuestro abierto: se cierra antes de arrancar")
                    try {
                        exerciseClient.endExercise()
                    } catch (e: Exception) {
                        Log.w(TAG, "no se pudo cerrar el ejercicio anterior", e)
                    }
                }

                exerciseClient.setUpdateCallback(callback)

                val dataTypes = setOf(DataType.HEART_RATE_BPM, DataType.CALORIES_TOTAL)

                // `prepareExercise` prende los sensores ANTES de arrancar, para
                // que el primer pulso no tarde medio minuto en aparecer.
                //
                // Sólo con HEART_RATE_BPM: `WarmUpConfig` acepta data types
                // DELTA, y `CALORIES_TOTAL` es agregado. Pasarlo hace que
                // Kotlin no encuentre el constructor público y falle con un
                // error engañoso sobre un constructor `internal`.
                exerciseClient.prepareExercise(
                    WarmUpConfig(
                        exerciseType = ExerciseType.WEIGHTLIFTING,
                        dataTypes = setOf(DataType.HEART_RATE_BPM),
                    ),
                )

                exerciseClient.startExercise(
                    ExerciseConfig(
                        exerciseType = ExerciseType.WEIGHTLIFTING,
                        dataTypes = dataTypes,
                        // Sin GPS en v1: un entreno de pesas es indoor y el GPS
                        // sólo quemaría batería.
                        isAutoPauseAndResumeEnabled = false,
                        isGpsEnabled = false,
                    ),
                )
                Log.i(TAG, "ejercicio arrancado")
            } catch (e: Exception) {
                // Se loguea y se libera el guard: si falla por permisos, el
                // atleta puede otorgarlos y reintentar sin reiniciar la app.
                Log.w(TAG, "no se pudo arrancar el ejercicio", e)
                started = false
            }
        }
    }

    @Synchronized
    fun stop() {
        val exerciseClient = client ?: return
        started = false
        latest = null
        kcalAccumulated = null
        scope.launch {
            try {
                exerciseClient.endExercise()
                Log.i(TAG, "ejercicio terminado a pedido")
            } catch (e: Exception) {
                Log.w(TAG, "no se pudo terminar el ejercicio", e)
            }
        }
    }
}
