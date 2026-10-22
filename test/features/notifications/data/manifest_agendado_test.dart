import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El aviso de fin de descanso (#1617) agenda una notificación con
/// `zonedSchedule`, y en Android eso depende de DOS líneas de manifest que no
/// se ven desde Dart:
///
/// - el `ScheduledNotificationReceiver` del plugin, que el sistema invoca al
///   vencer la alarma. Si falta, `zonedSchedule` agenda sin error y la
///   notificación NO sale nunca: el síntoma es el silencio;
/// - `SCHEDULE_EXACT_ALARM`, que habilita el modo exacto.
///
/// Van en `src/phone` y no en `src/main` a propósito: el manifest del reloj
/// afirma que NO declara permisos de alarmas exactas (ver `RestAlarm.kt`), y con
/// el permiso en `main` esa frase sería falsa para el APK de wear.
void main() {
  String leer(String ruta) {
    final archivo = File(ruta);
    expect(archivo.existsSync(), isTrue,
        reason: 'no se encontró $ruta — ¿corriste el test desde la raíz?');
    // Sin comentarios: los de estos manifests nombran los permisos para
    // explicar por qué NO están, y un match sobre el texto crudo los tomaría
    // por declaraciones.
    return archivo
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  }

  bool declaraPermiso(String xml, String permiso) => RegExp(
        '<uses-permission[^>]*android:name="android\\.permission\\.$permiso"',
      ).hasMatch(xml);

  late String phone;
  late String main_;
  late String wear;

  setUpAll(() {
    phone = leer('android/app/src/phone/AndroidManifest.xml');
    main_ = leer('android/app/src/main/AndroidManifest.xml');
    wear = leer('android/app/src/wear/AndroidManifest.xml');
  });

  test('el flavor phone declara el receiver que dibuja la agendada', () {
    expect(
      RegExp(
        r'<receiver[^>]*android:name="com\.dexterous\.flutterlocalnotifications'
        r'\.ScheduledNotificationReceiver"[^>]*android:exported="false"',
      ).hasMatch(phone),
      isTrue,
      reason: 'sin el receiver, zonedSchedule agenda y el aviso nunca sale',
    );
  });

  test('el flavor phone declara SCHEDULE_EXACT_ALARM', () {
    expect(declaraPermiso(phone, 'SCHEDULE_EXACT_ALARM'), isTrue);
  });

  // Control negativo de los de arriba: si el permiso se moviera a `main`, los
  // dos tests de arriba seguirían en verde mirando sólo `phone`.
  test('main y wear NO declaran SCHEDULE_EXACT_ALARM', () {
    expect(declaraPermiso(main_, 'SCHEDULE_EXACT_ALARM'), isFalse,
        reason: 'lo heredaría el APK del reloj, que dice no declararlo');
    expect(declaraPermiso(wear, 'SCHEDULE_EXACT_ALARM'), isFalse);
  });

  test('en ningún manifest se declara USE_EXACT_ALARM', () {
    for (final xml in [phone, main_, wear]) {
      expect(declaraPermiso(xml, 'USE_EXACT_ALARM'), isFalse);
    }
  });
}
