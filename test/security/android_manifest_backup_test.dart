// QA-SEC-100 — guard de política de backup de Android.
//
// El SDK de Firebase Auth persiste la sesión autenticada en SharedPreferences
// (`com.google.firebase.auth.api.Store.<app-id>`). Si Android Auto Backup /
// transferencia device-to-device quedan habilitados (el default cuando el
// `<application>` no declara `android:allowBackup`), esa sesión —y el resto de
// los datos privados de la app— se respaldan al Drive del usuario y son
// restaurables en otro dispositivo (MASVS MSTG-STORAGE-8).
//
// Test estático: parsea el manifest real y falla si no está `allowBackup="false"`.
// No existía red de seguridad para la config del manifest; esta es esa red.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QA-SEC-100: política de backup en AndroidManifest', () {
    late String manifest;

    setUpAll(() {
      // `flutter test` corre desde la raíz del paquete, así que el path relativo
      // resuelve contra el root del proyecto.
      final file = File('android/app/src/main/AndroidManifest.xml');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'No se encontró AndroidManifest.xml en ${file.absolute.path}',
      );
      manifest = file.readAsStringSync();
    });

    test('el <application> declara android:allowBackup="false"', () {
      expect(
        RegExp(r'android:allowBackup\s*=\s*"false"').hasMatch(manifest),
        isTrue,
        reason:
            'AndroidManifest.xml debe declarar android:allowBackup="false" para '
            'que la sesión de Firebase Auth y los datos privados no salgan del '
            'device vía Auto Backup / device-to-device (QA-SEC-100).',
      );
    });

    test('nunca se habilita allowBackup="true"', () {
      expect(
        RegExp(r'android:allowBackup\s*=\s*"true"').hasMatch(manifest),
        isFalse,
        reason: 'allowBackup no debe estar en "true": reabre la fuga de sesión.',
      );
    });
  });
}
