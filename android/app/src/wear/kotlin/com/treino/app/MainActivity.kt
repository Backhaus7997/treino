package com.treino.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewConfiguration
import io.flutter.plugin.common.EventChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.treino.app.link.TreinoLinkPlugin
import com.treino.app.workout.WearWorkoutPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var wearWorkout: WearWorkoutPlugin? = null

    /// El canal simétrico con el teléfono. Ver TreinoLinkPlugin.
    private var link: TreinoLinkPlugin? = null

    private var rotarySink: EventChannel.EventSink? = null

    /// Se cachea: la corona emite a decenas de eventos por segundo y leer
    /// recursos en cada uno es tirar CPU (y bateria) al pedo.
    private val scrollFactor: Float by lazy {
        ViewConfiguration.get(this).scaledVerticalScrollFactor
    }

    /// La corona / bisel giratorio del reloj.
    ///
    /// **El engine de Flutter TIRA estos eventos.** No es un bug de version ni
    /// algo que arregle una actualizacion: `AndroidTouchProcessor
    /// .onGenericMotionEvent` exige `SOURCE_CLASS_POINTER`, y el rotary es
    /// `SOURCE_CLASS_NONE` (`0x00400000 and 0x2 == 0`), asi que sale por el
    /// primer `if`. No hay una sola mencion de `SOURCE_ROTARY_ENCODER` en todo
    /// flutter/flutter. `FlutterView` devuelve false y el evento burbujea hasta
    /// aca, que es donde lo agarramos.
    ///
    /// La corona NO es un gesto tactil: llega como `MotionEvent` con
    /// `ACTION_SCROLL` y el giro vive en el eje `AXIS_SCROLL`.
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_SCROLL &&
            // `isFromSource`, NUNCA `event.source == SOURCE_ROTARY_ENCODER`:
            // el source es un bitmask y la comparacion directa falla.
            event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            val sink = rotarySink
            if (sink != null) {
                // El menos NO es opcional: es lo que hace AOSP en
                // `AndroidComposeView.handleRotaryEvent`. Positivo = bajar.
                // El resultado son PIXELES FISICOS; Dart los pasa a logicos.
                val px = -event.getAxisValue(MotionEvent.AXIS_SCROLL) * scrollFactor
                sink.success(px.toDouble())
                return true
            }
        }
        return super.onGenericMotionEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // El servicio lo tiene que arrancar la Activity VISIBLE: la precondición
        // de runtime del foreground service tipo `health` es while-in-use, así
        // que arrancarlo desde un receiver con la app cerrada tira SecurityException.
        wearWorkout = WearWorkoutPlugin(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        link = TreinoLinkPlugin(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        requestBodySensorsIfNeeded()

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ROTARY_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    rotarySink = sink
                }

                override fun onCancel(args: Any?) {
                    rotarySink = null
                }
            })
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wearWorkout?.dispose()
        wearWorkout = null
        rotarySink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /// Pide el permiso que habilita el pulso de Health Services.
    ///
    /// Se pide desde la Activity VISIBLE porque es while-in-use.
    ///
    /// ## Cual de los dos, y por que
    ///
    /// MEDIDO en un Samsung SM-L500 con Wear OS 6 (API 36) y la app en
    /// targetSdk 35: `startExercise` tiro
    /// `SecurityException: Missing permissions:
    /// [android.permission.health.READ_HEART_RATE]`.
    ///
    /// O sea que manda la version del DISPOSITIVO, no el targetSdkVersion de
    /// la app como sostiene la documentacion. Por eso el corte es por
    /// `Build.VERSION.SDK_INT` y no por el target.
    ///
    /// NUNCA pedir BODY_SENSORS y BODY_SENSORS_BACKGROUND juntos: la doc avisa
    /// que el sistema ignora el pedido y no otorga NINGUNO de los dos.
    private fun requestBodySensorsIfNeeded() {
        val heartRate = if (Build.VERSION.SDK_INT >= 36) {
            "android.permission.health.READ_HEART_RATE"
        } else {
            Manifest.permission.BODY_SENSORS
        }
        // ACTIVITY_RECOGNITION va SIEMPRE: sin el, `startExercise` falla aunque
        // el de pulso este otorgado. Y el sintoma engana, porque el pulso se ve
        // igual (lo entrega el calentamiento) y solo faltan las calorias.
        val faltantes = listOf(heartRate, Manifest.permission.ACTIVITY_RECOGNITION)
            .filter {
                ContextCompat.checkSelfPermission(this, it) !=
                    PackageManager.PERMISSION_GRANTED
            }
        if (faltantes.isEmpty()) return
        ActivityCompat.requestPermissions(this, faltantes.toTypedArray(), REQ_HEART_RATE)
    }

    override fun onDestroy() {
        // El canal registra un listener en Play Services; sin soltarlo queda
        // una referencia a la Activity muerta.
        link?.dispose()
        link = null
        super.onDestroy()
    }

    private companion object {
        const val REQ_HEART_RATE = 0x5E45
        const val ROTARY_CHANNEL = "treino/wear_rotary"
    }
}
