package com.treino.app

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wearWorkout?.dispose()
        wearWorkout = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
