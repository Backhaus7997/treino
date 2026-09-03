package com.treino.app

import com.treino.app.link.TreinoLinkPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// Activity del APK del TELÉFONO.
///
/// Casi pelada a propósito: el foreground service de tipo `health`, Health
/// Services y el platform channel del entreno viven en `src/wear/`. El teléfono
/// no tiene sensores de muñeca ni corre entrenos, así que no tiene por qué
/// cargar nada de eso ni declarar sus permisos.
///
/// Lo único que sí registra es [TreinoLinkPlugin], porque el canal con el reloj
/// es SIMÉTRICO: este lado manda los avisos —"arranqué un entreno"— y escucha
/// los que vienen de la muñeca.
class MainActivity : FlutterActivity() {

    private var link: TreinoLinkPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        link = TreinoLinkPlugin(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        link?.dispose()
        link = null
        super.onDestroy()
    }
}
