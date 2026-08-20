package com.treino.app.workout

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

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
        Log.i(TAG, "llego un mensaje en ${event.path}")
        if (event.path != PATH_WORKOUT_STARTED) return

        // El payload viaja como JSON, no como serializacion de Java: asi este
        // servicio lo parsea sin engine de Flutter y sin ObjectInputStream.
        val datos = try {
            JSONObject(String(event.data, Charsets.UTF_8))
        } catch (e: Exception) {
            Log.w(TAG, "payload ilegible, se abre igual", e)
            JSONObject()
        }

        WorkoutLauncher.abrir(this, "data layer $datos")
    }

    private companion object {
        private const val TAG = "treino-wear-launch"

        /** Espeja `TreinoLink.pathWorkoutStarted` del lado Dart. */
        private const val PATH_WORKOUT_STARTED = "/treino/workout-started"
    }
}
