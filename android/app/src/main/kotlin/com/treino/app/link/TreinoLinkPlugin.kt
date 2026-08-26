package com.treino.app.link

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Canal propio entre el telefono y el reloj, sobre la Data Layer API.
 *
 * ## Por que no alcanza `watch_connectivity`
 *
 * El plugin manda los mensajes con `path = "watch_connectivity"`, SIN barra
 * inicial, mientras que para los DataItems usa `"/watch_connectivity"` CON
 * barra. Es inconsistente consigo mismo, y esa inconsistencia tiene una
 * consecuencia que costo una corrida en hardware descubrir:
 *
 * Play Services despacha los mensajes a los `WearableListenerService`
 * declarados en el manifest armando un Intent con URI `wear://<nodo>/<path>`.
 * Con un path sin barra inicial esa URI queda malformada y NINGUN filtro la
 * matchea. El listener registrado en runtime, en cambio, recibe todo sin mirar
 * el path — por eso los avisos funcionan con la app abierta y el servicio
 * declarativo no se despierta jamas.
 *
 * O sea: con ese plugin es IMPOSIBLE que el reloj reaccione con la app cerrada.
 *
 * ## Que hace este canal distinto
 *
 * 1. **Los paths los elige quien llama, y se validan.** Tienen que empezar con
 *    `/`, asi que el despacho declarativo funciona.
 * 2. **El payload es JSON**, no serializacion de Java. Un `WearableListenerService`
 *    puede parsearlo con `org.json` sin arrastrar `ObjectInputStream`, y el
 *    formato se lee igual desde Dart, Kotlin o Swift.
 * 3. **Vive en `src/main`**, asi que lo comparten el APK del telefono y el del
 *    reloj. El canal es simetrico por definicion: los dos mandan y los dos
 *    escuchan.
 */
class TreinoLinkPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    MessageClient.OnMessageReceivedListener {

    private val method = MethodChannel(messenger, CHANNEL_METHODS)
    private val events = EventChannel(messenger, CHANNEL_MESSAGES)
    private val messageClient = Wearable.getMessageClient(context)

    private var sink: EventChannel.EventSink? = null

    init {
        method.setMethodCallHandler(this)
        events.setStreamHandler(this)
        messageClient.addListener(this)
    }

    fun dispose() {
        method.setMethodCallHandler(null)
        events.setStreamHandler(null)
        messageClient.removeListener(this)
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> send(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Manda [payload] a todos los nodos conectados, en [path].
     *
     * Devuelve si habia al menos un nodo al que mandarselo. NO espera la
     * confirmacion de entrega: un aviso es best-effort por naturaleza, y hacer
     * esperar a Dart por la red seria repetir el error de esperar el ack de
     * Firestore para mover la UI.
     */
    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val payload = call.argument<String>("payload") ?: "{}"

        // La barra inicial es LA razon de que este canal exista. Sin ella el
        // mensaje viaja igual pero no despierta a nadie con la app cerrada, que
        // es justo el caso que hay que cubrir. Falla ruidoso en vez de degradar
        // en silencio.
        if (path.isNullOrEmpty() || !path.startsWith("/")) {
            result.error("bad_path", "El path tiene que empezar con '/': $path", null)
            return
        }

        Wearable.getNodeClient(context).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.i(TAG, "no hay nodos conectados, se descarta $path")
                    result.success(false)
                    return@addOnSuccessListener
                }
                val bytes = payload.toByteArray(Charsets.UTF_8)
                nodes.forEach { messageClient.sendMessage(it.id, path, bytes) }
                Log.i(TAG, "enviado $path a ${nodes.size} nodo(s)")
                result.success(true)
            }
            .addOnFailureListener {
                Log.w(TAG, "no se pudieron listar los nodos", it)
                result.success(false)
            }
    }

    override fun onMessageReceived(event: MessageEvent) {
        sink?.success(
            mapOf(
                "path" to event.path,
                "payload" to String(event.data, Charsets.UTF_8),
            )
        )
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    companion object {
        private const val TAG = "treino-link"
        const val CHANNEL_METHODS = "treino/link"
        const val CHANNEL_MESSAGES = "treino/link/messages"

        /** Prefijo de todos los paths. Lo espeja el intent-filter del manifest. */
        const val PATH_PREFIX = "/treino"
    }
}
