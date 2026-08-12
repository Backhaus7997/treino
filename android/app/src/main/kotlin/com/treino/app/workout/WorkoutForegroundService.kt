package com.treino.app.workout

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log

/**
 * Foreground service que mantiene VIVO el proceso durante un entreno.
 *
 * ## Qué mitad es ésta, y qué NO hace
 *
 * En watchOS hicieron falta DOS mitades y ninguna alcanzaba sola:
 * `HKWorkoutSession` **y** el background mode declarado. En Android el reparto
 * es distinto y hay que tenerlo clarísimo:
 *
 * * **Este servicio** es lo que pelea contra el congelamiento del proceso. Un
 *   proceso con foreground service nunca entra en estado `cached`, así que el
 *   freezer de cgroup v2 —activo por default desde Android 12, verificado con
 *   `use_freezer=true` en el propio emulador de Wear— no lo puede `SIGSTOP`ear.
 * * **Health Services / `ExerciseClient`** NO mantiene vivo nada. Trackea en el
 *   MCU, fuera de nuestro proceso, y nos entrega datos. La propia doc de Google
 *   te manda a hacer esto: "Use a continuously running ForegroundService in
 *   conjunction with ExerciseClient".
 *
 * O sea que son mitades COMPLEMENTARIAS, no redundantes. Ésa es la asimetría
 * con watchOS y es la predicción falsable de este ciclo.
 *
 * Lo que este servicio NO da, y conviene no ilusionarse:
 * * NO impide que el DISPOSITIVO entre en Doze.
 * * NO mantiene la CPU despierta por sí solo.
 * * NO protege al `FlutterEngine` si la Activity se DESTRUYE — protege al
 *   proceso, no al engine.
 *
 * ## Los interruptores
 *
 * [EXTRA_WITH_ONGOING] existe para poder poner ROJA una mitad por vez sin tocar
 * el manifest. Quitar `foregroundServiceType` del manifest NO sirve como control
 * rojo: tira `IllegalArgumentException` y entonces no medís supervivencia, medís
 * un crash.
 */
class WorkoutForegroundService : Service() {

    companion object {
        private const val TAG = "TreinoFGS"
        private const val CHANNEL_ID = "treino_workout"
        private const val NOTIF_ID = 0x7EE1

        const val ACTION_START = "com.treino.app.workout.START"
        const val ACTION_STOP = "com.treino.app.workout.STOP"

        /** Si se publica una Ongoing Activity además del foreground service. */
        const val EXTRA_WITH_ONGOING = "withOngoing"

        /** Instante en que arrancó el entreno, para el cronómetro de la notificación. */
        const val EXTRA_STARTED_AT_ELAPSED = "startedAtElapsed"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "stop pedido")
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val withOngoing = intent?.getBooleanExtra(EXTRA_WITH_ONGOING, true) ?: true
        val startedAt = intent?.getLongExtra(EXTRA_STARTED_AT_ELAPSED, SystemClock.elapsedRealtime())
            ?: SystemClock.elapsedRealtime()

        ensureChannel()
        val notification = buildNotification(startedAt, withOngoing)

        // El tipo `health` recién se enforcea desde API 34. Por debajo, el
        // overload de 2 args toma el tipo del manifest, que es lo correcto.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        Log.i(TAG, "foreground arrancado withOngoing=$withOngoing elapsed=$startedAt")
        // START_STICKY: si el sistema igual nos mata, que nos reviva. Es
        // deliberado — un entreno a medias no se abandona en silencio.
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "destruido elapsed=${SystemClock.elapsedRealtime()}")
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        mgr.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Entreno en curso",
                // LOW: sin sonido. El descanso avisa por su cuenta; la
                // notificación del servicio es sólo el anclaje de la sesión.
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun buildNotification(startedAtElapsed: Long, withOngoing: Boolean): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val touch = PendingIntent.getActivity(
            this,
            0,
            launch ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("Entreno en curso")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(touch)
            .setOngoing(true)
            // El cronómetro lo renderiza el SISTEMA a partir de la base, así que
            // no hay que re-postear la notificación cada segundo. Repostear cada
            // segundo es justo el patrón que despierta al SoC y quema batería.
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis() - (SystemClock.elapsedRealtime() - startedAtElapsed))

        if (withOngoing) {
            // Ongoing Activity va acá cuando entre androidx.wear:wear-ongoing.
            // Hoy el flag sólo marca la intención para que la matriz de medición
            // tenga la celda, sin fingir que ya está implementada.
            builder.setCategory(Notification.CATEGORY_WORKOUT)
        }

        return builder.build()
    }
}
