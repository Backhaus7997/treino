package com.treino.app.workout

import android.app.AlarmManager
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
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
    }

    private val alarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

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
        vibrate()
    }

    /** Agenda el aviso para el fin de [deadline]. Reemplaza cualquier anterior. */
    fun schedule(deadline: RestDeadline) {
        cancel()
        scheduledAtElapsedMs = deadline.endsAtElapsedMs
        alarmManager.setExact(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            deadline.endsAtElapsedMs,
            ALARM_TAG,
            listener,
            handler,
        )
        val enMs = deadline.endsAtElapsedMs - SystemClock.elapsedRealtime()
        Log.i(TAG, "agendada para elapsed=${deadline.endsAtElapsedMs} (en ${enMs}ms)")
    }

    fun cancel() {
        if (scheduledAtElapsedMs != null) {
            alarmManager.cancel(listener)
            Log.i(TAG, "cancelada")
        }
        scheduledAtElapsedMs = null
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
