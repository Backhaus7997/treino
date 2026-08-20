package com.treino.app.workout

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Recibe el aviso de "arranco un entreno" por FCM y abre el companion.
 *
 * ## Por que FCM ademas de la Data Layer
 *
 * La Data Layer exige que el reloj este emparejado con ESE telefono y que el
 * telefono tenga la app companion instalada. Medido en hardware: en un telefono
 * sin companion, Play Services responde `Wearable.API is not available on this
 * device` y el aviso no sale nunca.
 *
 * FCM no necesita nada de eso. Al reloj le alcanza con tener internet — que ya
 * lo tiene, porque habla Firestore por Wi-Fi sin depender del telefono. A
 * cambio tarda segundos y depende de la red.
 *
 * Llega el que llegue primero. Abrir dos veces no hace daño: `MainActivity` es
 * `singleTop`.
 *
 * ## Por que un service NATIVO y no `onBackgroundMessage` de Dart
 *
 * El camino de Dart arranca un isolate de Flutter entero para decidir abrir una
 * pantalla, y encima necesita que el plugin este registrado en ESE isolate —
 * cosa que `TreinoLinkPlugin` no cumple, porque lo instancia la Activity. Tres
 * lineas de Kotlin hacen lo mismo sin levantar un engine.
 *
 * ## El riesgo, y por que se acepta
 *
 * FCM entrega cada mensaje a UN solo service, y el APK ya trae dos declarados
 * por `firebase_messaging` (viene por pubspec aunque el reloj no lo use).
 * Declarar este tercero puede quitarle mensajes a ese plugin — **en el reloj**,
 * donde no se usa para nada: `main_wear.dart` no lo toca. En el APK del
 * telefono, que es donde las notificaciones importan de verdad, no se declara
 * nada.
 *
 * Si algun dia el reloj necesita FCM para otra cosa, esto hay que repensarlo.
 */
class WearMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val tipo = message.data[KEY_TYPE]
        Log.i(TAG, "push recibido (type=$tipo)")
        if (tipo != TYPE_WORKOUT_STARTED) return
        WorkoutLauncher.abrir(this, "fcm")
    }

    private companion object {
        private const val TAG = "treino-wear-fcm"

        /** Espeja el `data` que arma la Cloud Function. */
        private const val KEY_TYPE = "type"
        private const val TYPE_WORKOUT_STARTED = "workoutStarted"
    }
}
