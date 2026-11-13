/// Stub de `before_unload_guard_web.dart` para todo lo que NO es web (la VM de
/// los tests, Android, iOS). Mismo patrón que `browser_download_stub.dart`, con
/// una diferencia a propósito: acá es un no-op y no un `UnsupportedError`,
/// porque la pantalla que lo pide corre en los tests de widgets y el problema
/// que resuelve —recargar o cerrar la pestaña— no existe fuera del navegador.
void armBeforeUnload() {}

/// No hay nada que apagar fuera de web. Ver `before_unload_guard_web.dart`.
void disarmBeforeUnload() {}
