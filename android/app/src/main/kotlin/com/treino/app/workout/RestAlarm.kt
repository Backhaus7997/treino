package com.treino.app.workout

import android.app.AlarmManager
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Despertador del descanso.
 *
 * ## Por qué hace falta, si ya está el foreground service
 *
 * El foreground service resuelve "el proceso está vivo" — medido en un Samsung
 * SM-L500: 1109 callbacks sobre 1109.5 s de SoC despierto, cero salteados. Pero
 * NO resuelve "el SoC se despierta a tiempo". En esa misma corrida hubo 159 s de
 * suspensión real del procesador, y durante la suspensión no ejecuta código
 * nadie.
 *
 * Consecuencia medida: **el descanso llegó a cero en silencio.** El cronómetro
 * mostraba el número correcto —porque es un deadline, no un contador— pero el
 * aviso nunca existió. Un descanso no es un número, es un aviso: el atleta mira
 * la muñeca justamente cuando tiene que volver a la barra.
 *
 * ## Por qué ESTE mecanismo y no otro
 *
 * **Reloj `ELAPSED_REALTIME_WAKEUP`**: misma base `CLOCK_BOOTTIME` que
 * [SystemClock.elapsedRealtime], que es exactamente lo que [RestDeadline] ya
 * persiste. El valor se pasa tal cual, sin convertir, y queda inmune a saltos de
 * NTP y a cambios de zona horaria. `setAlarmClock` usa wall clock (RTC), obliga
 * a convertir y expone justo a esos saltos.
 *
 * **Variante con [AlarmManager.OnAlarmListener] y no con `PendingIntent`**: la
 * doc de Android 14 es explícita — *"If the exact alarm is set using an
 * OnAlarmListener object, like in the setExact API, the SCHEDULE_EXACT_ALARM
 * permission isn't required."* Ese permiso viene denegado por default desde
 * Android 14 para targets 33+, salvo apps de despertador o calendario, y
 * `USE_EXACT_ALARM` lo restringe Play a apps cuyo core ES un temporizador. Un
 * descanso adentro de una app de fitness es zona gris y puede frenar la
 * publicación. Con el listener el problema no existe.
 *
 * El tradeoff, explícito: **el listener está atado al proceso.** Si el proceso
 * muere, la alarma muere con él. Un `PendingIntent` a un receiver del manifest
 * sobreviviría, pero ésa es la variante que SÍ pide el permiso. Mantener vivo el
 * proceso es precisamente lo que el foreground service ya garantiza, así que las
 * dos piezas se sostienen mutuamente.
 *
 * ## La vibración va acá, no en Dart
 *
 * En background sólo se permiten hápticas atencionales, y para eso hay que
 * declarar la intención con `USAGE_ALARM`. Además, si la alarma dispara mientras
 * el isolate está dormido, mandarlo a Dart agrega latencia justo donde se está
 * midiendo puntualidad.
 */
class RestAlarm(private val context: Context) {

    private companion object {
        const val TAG = "TreinoRestAlarm"
        const val ALARM_TAG = "treino.rest"
        /** El prefijo `treino:` es convencion de Android para wakelocks de app. */
        const val WAKELOCK_TAG = "treino:rest"
        /** Margen sobre el deadline, para que el timeout no corte justo antes. */
        const val WAKELOCK_MARGIN_MS = 5_000L
    }

    private val alarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    /**
     * Wakelock parcial acotado al descanso.
     *
     * ## Qué arregla y qué NO
     *
     * **Doze IGNORA los wakelocks.** Sostener uno NO evita que Doze difiera la
     * alarma — medido: `setExact` corrida +21m10s por `device_idle`. Lo que un
     * wakelock parcial sí impide es la **suspensión del SoC**, que es otra cosa.
     *
     * Y ahí está el punto: con el procesador despierto, el `Timer.periodic` de
     * Dart sigue corriendo, la app detecta por su cuenta que el deadline venció,
     * y vibra. **Sin AlarmManager de por medio, o sea sin permiso especial.**
     * Es la ruta que esquiva la decisión entre `USE_EXACT_ALARM` (riesgo de
     * política de Play) y `SCHEDULE_EXACT_ALARM` (fricción de UX).
     *
     * ## Por qué acotado, y por qué esto no contradice a Google
     *
     * Google pide no tomar wakelocks en entrenos LARGOS: *"in health & fitness
     * apps, long-running workouts don't need a wakelock"*. Un wakelock de 60-90 s
     * durante el descanso es otra cosa que sostenerlo la hora entera del entreno.
     * El costo de batería existe y es real, pero está acotado y es proporcional
     * al tiempo que el atleta está esperando un aviso.
     *
     * Se toma SIEMPRE con timeout: si algo sale mal y nadie lo suelta, el sistema
     * lo corta igual. Un wakelock filtrado le funde la batería al atleta sin que
     * nadie se entere hasta que es tarde.
     */
    private var wakeLock: PowerManager.WakeLock? = null

    /** Handler del main looper: el listener se invoca ahí. */
    private val handler = Handler(Looper.getMainLooper())

    /** Deadline agendado, para poder medir el error al disparar. */
    private var scheduledAtElapsedMs: Long? = null

    private val listener = AlarmManager.OnAlarmListener {
        val firedAt = SystemClock.elapsedRealtime()
        val target = scheduledAtElapsedMs
        // El error es el número que decide si esto sirve: cuánto tarde llegó el
        // aviso respecto del instante en que el descanso vencía de verdad.
        val errorMs = if (target != null) firedAt - target else Long.MIN_VALUE
        Log.i(TAG, "ALARMA disparo elapsed=$firedAt target=$target error=${errorMs}ms")
        scheduledAtElapsedMs = null
        releaseWakeLock()
        vibrate()
    }

    /**
     * Agenda el aviso para el fin de [deadline]. Reemplaza cualquier anterior.
     *
     * [holdWakeLock] mantiene el SoC despierto durante el descanso. Es el
     * interruptor del experimento: permite medir la puntualidad con y sin, sobre
     * el mismo código.
     */
    fun schedule(deadline: RestDeadline, holdWakeLock: Boolean) {
        cancel()
        scheduledAtElapsedMs = deadline.endsAtElapsedMs

        val enMs = deadline.endsAtElapsedMs - SystemClock.elapsedRealtime()

        if (holdWakeLock && enMs > 0) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG).apply {
                setReferenceCounted(false)
                // Timeout = lo que falta + margen. Red de seguridad: aunque
                // nadie lo suelte, el sistema lo corta.
                acquire(enMs + WAKELOCK_MARGIN_MS)
            }
            Log.i(TAG, "wakelock TOMADO por ${enMs + WAKELOCK_MARGIN_MS}ms")
        }

        alarmManager.setExact(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            deadline.endsAtElapsedMs,
            ALARM_TAG,
            listener,
            handler,
        )
        Log.i(
            TAG,
            "agendada para elapsed=${deadline.endsAtElapsedMs} " +
                "(en ${enMs}ms) wakelock=$holdWakeLock",
        )
    }

    fun cancel() {
        if (scheduledAtElapsedMs != null) {
            alarmManager.cancel(listener)
            Log.i(TAG, "cancelada")
        }
        scheduledAtElapsedMs = null
        releaseWakeLock()
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.i(TAG, "wakelock soltado")
            }
        }
        wakeLock = null
    }

    /**
     * El descanso venció y lo detectó la APP (el timer de Dart), no la alarma.
     *
     * Es el camino que el wakelock habilita: con el SoC despierto no hace falta
     * AlarmManager, así que tampoco hace falta ningún permiso especial. Se
     * loguea el error igual que el de la alarma, para poder compararlos.
     */
    fun onDeadlineNoticedByApp(target: Long) {
        val noticedAt = SystemClock.elapsedRealtime()
        Log.i(TAG, "APP detecto el vencimiento elapsed=$noticedAt target=$target error=${noticedAt - target}ms")
        releaseWakeLock()
    }

    private fun vibrate() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) {
            Log.w(TAG, "el dispositivo no vibra")
            return
        }

        // Patrón corto-corto-largo: se distingue de una notificación cualquiera
        // sin mirar la pantalla, que es el punto de un aviso de descanso.
        val pattern = longArrayOf(0, 200, 150, 200, 150, 500)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = VibrationEffect.createWaveform(pattern, -1)
            // USAGE_ALARM es lo que habilita la háptica con la app en background.
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            vibrator.vibrate(effect, attrs)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }
}
