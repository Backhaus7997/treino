// Implementación web de la defensa de Auth contra producción en modo emulador
// (#1692). La importa `emuladores.dart` con un conditional import; fuera de web
// se usa `auth_emulador_stub.dart`.
//
// Hace dos cosas, y las dos existen por lo mismo: `firebase_auth_web` 5.15.3
// restaura la sesión persistida POR RED dentro de `Firebase.initializeApp`
// (`ensurePluginInitialized` → `onWaitInitState`), o sea antes de que la app
// pueda llamar a `useAuthEmulator`. El SDK de JS no deja conectar un emulador
// una vez que Auth hizo un request (`auth/emulator-config-failed`) y el plugin
// ese código lo traga. Auth se queda en producción.
//
//  1. [borrarSesionPersistidaDeAuth] PREVIENE: antes de `initializeApp` borra
//     lo persistido, y sin sesión que restaurar Auth no hace ningún request.
//  2. [verificarAuthEnElEmulador] ENFORZA: después de `useAuthEmulator` lee el
//     estado real de Auth y frena la app si no quedó en el emulador.
//
// `dart:js_interop` y `package:web` NO se pueden probar en la VM: lo que se
// puede probar —la decisión— vive en `auth_emulador_guard.dart`.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'auth_emulador_guard.dart';

/// Nombres que usa el SDK de JS de Auth para persistir (`@firebase/auth`,
/// `indexed_db.ts` y `_persistenceKeyName`). Si cambian, [borrarSesionPersistidaDeAuth]
/// borra de menos y lo ataja [verificarAuthEnElEmulador].
const _baseDeAuth = 'firebaseLocalStorageDb';
const _almacenDeAuth = 'firebaseLocalStorage';
const _prefijoDelUsuario = 'firebase:authUser:';

// Módulos del SDK de JS que `firebase_core_web` deja colgados de `window`
// (`window.firebase_core`, `window.firebase_auth`). No hay un `<script>` de
// Firebase en `web/index.html`: los inyecta el plugin dentro de
// `Firebase.initializeApp`.
@JS('firebase_core.getApps')
external JSArray<JSAny?> _getApps();

@JS('firebase_core.getApp')
external _AppJs _getApp();

@JS('firebase_auth.getAuth')
external _AuthJs _getAuth(_AppJs app);

extension type _AppJs._(JSObject _) implements JSObject {}

extension type _AuthJs._(JSObject _) implements JSObject {
  /// `null` si Auth NO tiene emulador (habla con producción).
  external _EmulatorConfigJs? get emulatorConfig;
}

extension type _EmulatorConfigJs._(JSObject _) implements JSObject {
  external String get host;
  external int? get port;
}

/// Borra la sesión de Auth persistida en el navegador. Hay que llamarla ANTES
/// de `Firebase.initializeApp`, y sólo en modo emulador (ver
/// `limpiarSesionDeAuthParaEmulador`).
///
/// ⚠️ Costo, a propósito: en modo emulador una recarga CIERRA LA SESIÓN. Es el
/// precio de que Auth no tenga nada que restaurar contra producción. En un
/// build normal esto ni se compila.
///
/// Borra de los TRES lugares donde el SDK busca usuario: IndexedDB, y
/// `localStorage` y `sessionStorage` (`PersistenceUserManager.create` revisa
/// todas las persistencias, no sólo la elegida).
///
/// IndexedDB se VACÍA (`clear()` del object store) y no se borra la base:
/// `deleteDatabase` queda bloqueado mientras otro contexto tenga la base
/// abierta —otra pestaña, o esta misma después de un hot restart— porque el SDK
/// no atiende `versionchange`, y el `open()` de Firebase se encola detrás del
/// borrado. Es colgar el arranque sin decir nada.
Future<void> borrarSesionPersistidaDeAuth() async {
  // Hot restart (`flutter run -d chrome`): la página sigue viva y el SDK de JS
  // también, con Auth ya conectado al emulador y su sesión en memoria. No hay
  // nada que restaurar por red, y vaciar la base desloguearía en cada restart.
  if (_yaHayUnaAppDeFirebase()) return;

  _quitarUsuario(() => web.window.localStorage);
  _quitarUsuario(() => web.window.sessionStorage);
  await _vaciarIndexedDb();
}

bool _yaHayUnaAppDeFirebase() {
  // En una carga limpia `window.firebase_core` ni existe todavía: lo inyecta
  // `Firebase.initializeApp`.
  if (globalContext.getProperty<JSAny?>('firebase_core'.toJS) == null) {
    return false;
  }
  return _getApps().toDart.isNotEmpty;
}

void _quitarUsuario(web.Storage Function() storage) {
  try {
    final s = storage();
    // Primero se juntan las claves: borrar mientras se itera corre los índices.
    final claves = <String>[
      for (var i = 0; i < s.length; i++)
        if (s.key(i) case final clave?
            when clave.startsWith(_prefijoDelUsuario))
          clave,
    ];
    for (final clave in claves) {
      s.removeItem(clave);
    }
  } catch (_) {
    // El navegador no deja tocar el storage (cookies bloqueadas, modo
    // privado): el SDK tampoco puede persistir ahí, no hay nada que borrar.
  }
}

Future<void> _vaciarIndexedDb() {
  final listo = Completer<void>();
  var noExistia = false;

  // `open` SIN versión abre la que haya. Si la base no existe la CREA vacía y
  // dispara `upgradeneeded`: se aborta esa transacción, que la deja sin crear
  // (no hay sesión persistida), y el `open` termina en `error`. Crearla vacía
  // sería peor: el SDK de Auth la encuentra sin su object store y la borra y
  // recrea él mismo (su workaround de Firefox).
  final pedido = web.window.indexedDB.open(_baseDeAuth);

  pedido.onupgradeneeded = ((web.Event _) {
    noExistia = true;
    pedido.transaction?.abort();
  }).toJS;

  pedido.onerror = ((web.Event evento) {
    // Es el camino normal de "no existía" (`AbortError`). Cualquier otro error
    // al abrir significa que IndexedDB no anda, o sea que el SDK tampoco
    // persiste ahí.
    evento.preventDefault();
    if (!noExistia) {
      final aviso = 'auth_emulador: no pude abrir $_baseDeAuth para borrar '
          'la sesión: ${pedido.error?.message}';
      web.console.warn(aviso.toJS);
    }
    if (!listo.isCompleted) listo.complete();
  }).toJS;

  pedido.onsuccess = ((web.Event _) {
    final db = pedido.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_almacenDeAuth)) {
      db.close();
      listo.complete();
      return;
    }
    final tx = db.transaction(_almacenDeAuth.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) {
      db.close();
      listo.complete();
    }).toJS;
    // Acá sí se frena: la base existe, pudo tener una sesión, y si quedó
    // intacta Firebase la restauraría contra producción en el próximo paso.
    final fallo = ((web.Event _) {
      db.close();
      if (!listo.isCompleted) {
        listo.completeError(
          AuthFueraDelEmuladorError(
            'No pude vaciar $_baseDeAuth antes de arrancar Firebase: '
            '${tx.error?.message}. '
            'Sin eso el SDK restauraría la sesión contra PRODUCCIÓN antes de '
            'conectar el emulador (#1692). Cerrá las otras pestañas de la '
            'app, borrá los datos del sitio y recargá.',
          ),
        );
      }
    }).toJS;
    tx.onerror = fallo;
    tx.onabort = fallo;
    tx.objectStore(_almacenDeAuth).clear();
  }).toJS;

  // Un IndexedDB que no contesta dejaría el arranque colgado, en blanco y sin
  // decir por qué. Es mejor frenar a los gritos.
  return listo.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw AuthFueraDelEmuladorError(
      'IndexedDB no contestó en 10 s al vaciar $_baseDeAuth. Sin eso el SDK '
      'podría restaurar la sesión contra PRODUCCIÓN antes de conectar el '
      'emulador (#1692). Cerrá las otras pestañas de la app y recargá.',
    ),
  );
}

/// Lee de Auth —el SDK de JS, la instancia real que usa el plugin— a dónde
/// apunta, y tira [AuthFueraDelEmuladorError] si no es [host]:[port].
///
/// Se llama DESPUÉS de `useAuthEmulator`. No se puede preguntar por la API de
/// Dart: ni `FirebaseAuth` ni el wrapper del plugin exponen `emulatorConfig`,
/// y el `await useAuthEmulator` vuelve bien aun cuando falló (#1692).
///
/// `getAuth(app)` devuelve la instancia que el plugin ya inicializó en
/// `Firebase.initializeApp` (`provider.isInitialized()`); no crea otra.
void verificarAuthEnElEmulador(String host, int port) {
  DestinoDeAuth? configurado;
  try {
    final config = _getAuth(_getApp()).emulatorConfig;
    if (config != null) {
      configurado = (host: config.host, port: config.port);
    }
  } catch (e) {
    // Si no se puede leer, no se sabe: se frena igual. Un "no pude verificar"
    // que deja seguir es el mensaje tranquilizador falso de AGENTS.md §11.1.
    throw AuthFueraDelEmuladorError(
      'No pude leer el estado de Firebase Auth para confirmar que está en el '
      'emulador ($host:$port): $e. Probable cambio en el SDK de JS o en '
      'firebase_auth_web; revisá este archivo.',
    );
  }
  exigirAuthEnElEmulador(configurado: configurado, host: host, port: port);
}
