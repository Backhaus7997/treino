package com.treino.app.workout

import android.app.ActivityOptions
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.treino.app.MainActivity

/**
 * Trae el companion al frente cuando el entreno arranco en otro lado.
 *
 * ## Por que vive aparte de quien recibe el aviso
 *
 * El aviso puede llegar por DOS transportes y ninguno de los dos sirve solo:
 *
 * - **Data Layer** (`WorkoutLaunchService`): instantanea y sin internet, pero
 *   exige que el reloj este emparejado con ESE telefono, con la app companion
 *   instalada. Medido: en un telefono sin companion, Play Services responde
 *   `Wearable.API is not available on this device`.
 * - **FCM** (`WearMessagingService`): no necesita emparejamiento —al reloj le
 *   alcanza con tener internet, igual que ya hace con Firestore— pero tarda
 *   segundos y depende de la red.
 *
 * Llega el que llegue primero. Abrir dos veces no hace daño: `MainActivity` es
 * `singleTop`.
 *
 * ## Los dos caminos para abrir, y por que hacen falta los dos
 *
 * 1. `startActivity` directo. Es el limpio, pero Android 10+ bloquea los
 *    "background activity starts" y esto corre siempre en background. Cuando lo
 *    bloquea NO tira excepcion: lo anota y no pasa nada.
 * 2. Notificacion con `fullScreenIntent`, el mecanismo de alarmas y llamadas,
 *    pensado para abrir una pantalla con el equipo bloqueado. Si el sistema no
 *    la abre, degrada a notificacion tocable — que sigue sirviendo.
 *
 * El transporte decide si el aviso LLEGA; esto decide que pasa despues. Son
 * problemas distintos y por eso el codigo esta separado.
 */
object WorkoutLauncher {

    fun abrir(context: Context, motivo: String) {
        Log.i(TAG, "abriendo el companion ($motivo)")
        abrirDirecto(context)
        abrirPorNotificacion(context)
    }

    private fun intentDeLaApp(context: Context): Intent =
        Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

    private fun abrirDirecto(context: Context) {
        try {
            context.startActivity(intentDeLaApp(context))
        } catch (e: Exception) {
            // Cuando el sistema lo bloquea no llega por aca —lo anota y sigue—
            // pero un SecurityException si cae, y no puede tumbar a quien llamo.
            Log.w(TAG, "no se pudo abrir la app directo", e)
        }
    }

    private fun abrirPorNotificacion(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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
            context,
            0,
            intentDeLaApp(context),
            // CANCEL y no UPDATE: `FLAG_UPDATE_CURRENT` reusa el PendingIntent
            // que ya existe y sólo le refresca los extras — las opciones de
            // arranque quedan las del original. Medido: con UPDATE, el log
            // seguía diciendo `balAllowedByPiCreator: BSP.NONE` aunque el
            // opt-in estuviera en el código, porque el objeto reusado se había
            // creado sin él. Cancelar y rehacer garantiza opciones frescas.
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            opcionesDeArranque(),
        )

        val notif = NotificationCompat.Builder(context, CANAL)
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

    /**
     * El opt-in que hace que el full-screen intent pueda abrir la pantalla.
     *
     * MEDIDO en el SM-L500 (Wear OS 6 / API 36), y no es nada obvio: la
     * notificacion se mostraba bien, el SysUI de Samsung tomaba el
     * `fullScreenIntent` e intentaba lanzar la Activity con el permiso especial
     * del sistema de notificaciones —`realCallerStartMode:
     * MODE_BACKGROUND_ACTIVITY_START_ALLOWED`— y aun asi Android respondia
     * `BAL_BLOCK`. El motivo estaba en una sola linea del log:
     *
     *     balAllowedByPiCreator: BSP.NONE
     *     balRequireOptInByPendingIntentCreator: true
     *
     * Desde Android 14 no alcanza con que QUIEN DISPARA el PendingIntent tenga
     * permiso: el que lo CREA tiene que dar opt-in explicito. Un `PendingIntent`
     * armado sin opciones llega como `BSP.NONE` y el sistema lo bloquea aunque
     * todo lo demas este en orden.
     *
     * Devuelve null por debajo de API 34, donde esta API no existe y el
     * comportamiento anterior ya permitia el arranque.
     */
    private fun opcionesDeArranque(): android.os.Bundle? =
        if (Build.VERSION.SDK_INT >= 34) {
            ActivityOptions.makeBasic()
                .setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                )
                .toBundle()
        } else {
            null
        }

    private const val TAG = "treino-wear-launch"
    private const val CANAL = "treino_workout_launch"
    private const val NOTIF_ID = 4201
}
