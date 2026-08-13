package com.treino.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.treino.app.workout.WearWorkoutPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var wearWorkout: WearWorkoutPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // El servicio lo tiene que arrancar la Activity VISIBLE: la precondición
        // de runtime del foreground service tipo `health` es while-in-use, así
        // que arrancarlo desde un receiver con la app cerrada tira SecurityException.
        wearWorkout = WearWorkoutPlugin(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        requestBodySensorsIfNeeded()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wearWorkout?.dispose()
        wearWorkout = null
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

    private companion object {
        const val REQ_HEART_RATE = 0x5E45
    }
}
