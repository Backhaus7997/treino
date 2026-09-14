import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/data/local_notifications_service.dart';

/// El canal de notificaciones se declara en DOS lados que no se ven entre sí:
/// la constante de Dart (por donde salen las de primer plano) y el meta-data
/// del manifest (por donde el SDK de FCM dibuja las de background, sin pasar
/// por Dart).
///
/// Si se desincronizan, nada falla: las notificaciones siguen saliendo. Lo que
/// pasa es que salen por DOS canales, el usuario ve dos entradas de
/// configuración para la misma app, y silenciar una no silencia la otra. Un
/// síntoma que sólo se descubre mirando Ajustes en un teléfono real.
void main() {
  const rutaDelManifest = 'android/app/src/main/AndroidManifest.xml';
  const claveDelMetaData =
      'com.google.firebase.messaging.default_notification_channel_id';

  test('el meta-data del manifest usa el MISMO canal que kCanalDeAvisos', () {
    final manifest = File(rutaDelManifest);
    expect(manifest.existsSync(), isTrue,
        reason: 'no se encontró $rutaDelManifest — ¿corriste el test desde la '
            'raíz del repo?');

    final xml = manifest.readAsStringSync();

    // Control de que el test mira algo: si el meta-data desaparece, esto se
    // pone rojo en vez de pasar por vacuidad.
    expect(xml, contains(claveDelMetaData),
        reason: 'el manifest ya no declara $claveDelMetaData: las '
            'notificaciones de background vuelven a caer en el canal por '
            'defecto de FCM, distinto del de primer plano');

    // El `android:value` del bloque que sigue a esa clave.
    final bloque = RegExp(
      '${RegExp.escape(claveDelMetaData)}"\\s*\\n?\\s*android:value="([^"]+)"',
    ).firstMatch(xml);

    expect(bloque, isNotNull,
        reason: 'se encontró la clave $claveDelMetaData pero no se pudo leer '
            'su android:value — ¿cambió el formato del bloque?');

    expect(
      bloque!.group(1),
      equals(kCanalDeAvisos),
      reason: 'el manifest declara el canal "${bloque.group(1)}" y Dart usa '
          '"$kCanalDeAvisos". Background y primer plano saldrían por canales '
          'distintos y el usuario vería dos entradas de configuración.',
    );
  });
}
