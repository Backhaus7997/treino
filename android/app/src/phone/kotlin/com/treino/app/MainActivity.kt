package com.treino.app

import io.flutter.embedding.android.FlutterActivity

/// Activity del APK del TELÉFONO.
///
/// Pelada a propósito: el foreground service de tipo `health`, Health Services
/// y el platform channel del entreno viven en `src/wear/`. El teléfono no tiene
/// sensores de muñeca ni corre entrenos, así que no tiene por qué cargar nada
/// de eso ni declarar sus permisos.
class MainActivity : FlutterActivity()
