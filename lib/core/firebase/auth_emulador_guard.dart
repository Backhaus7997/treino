/// Destino al que Auth dice estar apuntando cuando tiene un emulador
/// configurado (`auth.emulatorConfig` del SDK de JS: host y puerto).
typedef DestinoDeAuth = ({String host, int? port});

/// Con `USE_EMULATOR=true` no se puede garantizar que Auth hable sólo con el
/// emulador. Se tira ANTES de que la app arranque: seguir sería mandar
/// credenciales de QA y de dev a PRODUCCIÓN (`treino-dev` lo es, AGENTS.md →
/// Entornos).
///
/// Es un `Error` y no una `Exception` a propósito: no hay nada que atrapar ni
/// reintentar. Es un bug de entorno y la app tiene que frenar.
class AuthFueraDelEmuladorError extends Error {
  AuthFueraDelEmuladorError(this.mensaje);

  final String mensaje;

  @override
  String toString() => 'AuthFueraDelEmuladorError: $mensaje';
}

/// Exige que Auth haya quedado apuntando a [host]:[port]; si no, tira
/// [AuthFueraDelEmuladorError].
///
/// [configurado] es lo que Auth dice de sí mismo, y `null` significa que no
/// tiene ningún emulador: habla con producción.
///
/// Es una función pura (sin Firebase, sin navegador) para poder probar la
/// decisión en la VM. Leer el estado real de Auth es cosa de cada plataforma
/// (`auth_emulador_web.dart`).
///
/// Existe porque en web `FirebaseAuth.useAuthEmulator` PUEDE FALLAR EN SILENCIO
/// (#1692). `firebase_auth_web` 5.15.3 restaura la sesión persistida, por red,
/// dentro de `Firebase.initializeApp` (`ensurePluginInitialized` espera
/// `onWaitInitState`). Cuando después se le pide el emulador, el SDK de JS tira
/// `auth/emulator-config-failed` —ya hizo un request— y el plugin ese código
/// lo traga a propósito (su comentario dice que es por el hot reload). Resultado:
/// `await useAuthEmulator(...)` vuelve bien y Auth queda en producción, con el
/// login de la QA mandando la contraseña a `identitytoolkit.googleapis.com`.
void exigirAuthEnElEmulador({
  required DestinoDeAuth? configurado,
  required String host,
  required int port,
}) {
  if (configurado == null) {
    throw AuthFueraDelEmuladorError(
      'USE_EMULATOR=true, pero Firebase Auth NO quedó conectado al emulador '
      '($host:$port): sigue apuntando a PRODUCCIÓN y el próximo login mandaría '
      'la contraseña a identitytoolkit.googleapis.com. '
      'Causa conocida: el SDK restauró una sesión persistida por red antes de '
      'poder conectar el emulador (#1692). '
      'Borrá los datos del sitio (IndexedDB firebaseLocalStorageDb) y '
      'recargá. Si vuelve a pasar, es un bug: no sigas probando contra esta '
      'pestaña.',
    );
  }
  if (configurado.host != host || configurado.port != port) {
    throw AuthFueraDelEmuladorError(
      'USE_EMULATOR=true, pero Firebase Auth quedó apuntando a '
      '${configurado.host}:${configurado.port} y se esperaba $host:$port. '
      'Una instancia de Auth sólo acepta un emulador, y ya había otro.',
    );
  }
}
