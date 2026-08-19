package com.treino.app.workout

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import com.treino.app.MainActivity
import java.io.ByteArrayInputStream
import java.io.ObjectInputStream

/**
 * Abre el companion cuando el atleta arranca un entreno DESDE EL TELEFONO.
 *
 * ## Por que hace falta un servicio y no alcanza con Dart
 *
 * El listener de mensajes del plugin `watch_connectivity` se registra en
 * `onAttachedToEngine`, o sea que solo existe mientras la app del reloj esta
 * CORRIENDO. Con la app cerrada —que es el caso normal: el atleta saca el
 * telefono, toca Empezar, y recien despues mira la muñeca— no hay nadie
 * escuchando y el mensaje se pierde.
 *
 * Un `WearableListenerService` declarado en el manifest lo instancia Play
 * Services aunque el proceso este muerto. Es el unico camino que funciona con
 * la app cerrada.
 *
 * ## Los DOS caminos para traer la app al frente
 *
 * Se intentan los dos a proposito, y no es cinturon con tiradores: cual de los
 * dos funciona depende de la version de Wear OS y no se puede saber sin medir.
 *
 * 1. `startActivity` directo. Es el camino limpio, pero Android 10+ bloquea los
 *    "background activity starts" y el servicio corre justamente en background.
 *    Cuando lo bloquea no tira excepcion: lo anota en logcat y no pasa nada.
 * 2. Una notificacion con `fullScreenIntent`. Es el mecanismo de las alarmas y
 *    las llamadas, y esta pensado para abrir una pantalla con el dispositivo
 *    bloqueado. Si el sistema decide no abrirla, degrada a notificacion — que
 *    sigue siendo util: el atleta toca y entra.
 *
 * Si los dos funcionan no se abre dos veces: `MainActivity` es `singleTop`.
 */
class WorkoutLaunchService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        val payload = leerPayload(event.data)
        if (payload == null) {
            Log.i(TAG, "mensaje ilegible en ${event.path}, se ignora")
            return
        }

        // El mismo contrato que usa `WatchNudgeService` del lado Dart. Por este
        // canal viaja mas de un tipo de aviso, asi que se filtra por los dos
        // campos y no solo por el path.
        if (payload["kind"] != KIND_REFRESH) return
        if (payload["reason"] != REASON_WORKOUT_STARTED) return

        Log.i(TAG, "el telefono arranco un entreno: abriendo el companion")
        abrirDirecto()
        abrirPorNotificacion()
    }

    /** El HashMap serializado que manda el plugin del otro lado. */
    private fun leerPayload(bytes: ByteArray): Map<*, *>? = try {
        ObjectInputStream(ByteArrayInputStream(bytes)).readObject() as? Map<*, *>
    } catch (e: Exception) {
        Log.w(TAG, "no se pudo deserializar el mensaje", e)
        null
    }

    private fun intentDeLaApp(): Intent =
        Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    private fun abrirDirecto() {
        try {
            startActivity(intentDeLaApp())
        } catch (e: Exception) {
            // Cuando el sistema lo bloquea no llega por aca —lo anota y sigue—
            // pero un SecurityException si cae, y no puede tumbar el servicio.
            Log.w(TAG, "no se pudo abrir la app directo", e)
        }
    }

    private fun abrirPorNotificacion() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CANAL,
                "Entreno iniciado",
                // IMPORTANCE_HIGH es la precondicion del full-screen intent: con
                // una importancia menor el sistema ni lo evalua.
                NotificationManager.IMPORTANCE_HIGH,
            )
        )

        val pending = PendingIntent.getActivity(
            this,
            0,
            intentDeLaApp(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notif = NotificationCompat.Builder(this, CANAL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Entreno en curso")
            .setContentText("Segui desde el reloj")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .setFullScreenIntent(pending, true)
            .build()

        manager.notify(NOTIF_ID, notif)
    }

    companion object {
        private const val TAG = "treino-wear-launch"

        /** Espeja `WatchNudgeService.kind` del lado Dart. */
        private const val KIND_REFRESH = "watchRefresh"

        /** Espeja `WatchNudgeService.reasonWorkoutStarted`. */
        private const val REASON_WORKOUT_STARTED = "workoutStarted"

        private const val CANAL = "treino_workout_launch"
        private const val NOTIF_ID = 4201
    }
}
