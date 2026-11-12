// Stub de `auth_emulador_web.dart` para todo lo que NO es web (VM de los tests,
// Android, iOS). Mismo patrón que `browser_download_stub.dart`.
//
// Es un no-op a propósito: el problema es de web. Ahí el plugin restaura la
// sesión por red DENTRO de `Firebase.initializeApp`, antes de que la app pueda
// pedir el emulador. En Android se midió (QA del 2026-11-06, `logcat`) que Auth
// va a `:9099`, y no hay nada persistido en IndexedDB que limpiar. iOS NO se
// midió: si algún día el login de un build iOS con `USE_EMULATOR` sale a
// producción, acá es donde falta la verificación.

/// No hay nada que borrar fuera de web. Ver `auth_emulador_web.dart`.
Future<void> borrarSesionPersistidaDeAuth() async {}

/// No hay nada que verificar fuera de web. Ver `auth_emulador_web.dart`.
void verificarAuthEnElEmulador(String host, int port) {}
