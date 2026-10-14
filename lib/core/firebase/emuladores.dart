import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Si esta compilación corre contra los emuladores
/// (`--dart-define=USE_EMULATOR=true`).
const kUsaEmuladores = bool.fromEnvironment('USE_EMULATOR');

/// Puerto del emulador de Storage. Lo comparten [conectarEmuladores] y
/// [esUrlDeDescargaDelEmuladorDeStorage]: si cambia en uno, cambia en el otro.
const kPuertoEmuladorStorage = 9199;

/// Pisa [kUsaEmuladores] SÓLO en tests, al estilo de
/// `debugDefaultTargetPlatformOverride`. Quien lo setea lo vuelve a `null` en
/// un `addTearDown`. En release no tiene efecto.
@visibleForTesting
bool? debugUsaEmuladoresOverride;

/// Hosts con los que el emulador de Storage arma sus URLs de descarga:
/// `localhost` es el que fija [conectarEmuladores] y el que estampan los
/// scripts (`FIREBASE_STORAGE_EMULATOR_HOST`, que también puede venir como
/// `127.0.0.1`), y `10.0.2.2` es al que FlutterFire lo reescribe en Android
/// (`FirebaseStorage.useStorageEmulator`, firebase_storage 12.4.10).
const _hostsDelEmuladorDeStorage = {'localhost', '127.0.0.1', '10.0.2.2'};

/// True si [uri] es una URL de descarga del emulador de Storage
/// (`http://localhost:9199/v0/b/<bucket>/o/<path>?alt=media&token=…`) y la app
/// corre contra los emuladores.
///
/// Existe porque los gates de "¿esto es Storage?" sólo aceptaban
/// `firebasestorage.googleapis.com`, y en modo emulador NINGÚN video
/// reproducía: ni los que sube la propia app (`getDownloadURL()` contra el
/// emulador devuelve una URL de `localhost`, medido en el simulador de iOS)
/// ni los que estampan los scripts de Storage corridos contra el emulador
/// (#1444).
///
/// No abre el gate a nada más: sin `USE_EMULATOR`, o en release, devuelve
/// `false` siempre; y aun en modo emulador exige `http`, uno de los tres hosts
/// de arriba, el puerto del emulador y la forma `/v0/b/…/o/…`.
bool esUrlDeDescargaDelEmuladorDeStorage(Uri uri) {
  if (kReleaseMode) return false;
  if (!(debugUsaEmuladoresOverride ?? kUsaEmuladores)) return false;
  final segs = uri.pathSegments;
  return uri.scheme == 'http' &&
      _hostsDelEmuladorDeStorage.contains(uri.host) &&
      uri.port == kPuertoEmuladorStorage &&
      segs.length >= 5 &&
      segs[0] == 'v0' &&
      segs[1] == 'b' &&
      segs[3] == 'o';
}

/// Región de TODOS los callables del proyecto. `instanceFor` cachea por
/// región, así que el redirect al emulador sólo alcanza a la instancia de
/// ESTA región: un callable en otra —o en `FirebaseFunctions.instance`, que es
/// `us-central1`— seguiría yendo a producción. Lo fija
/// `test/app/guards/emuladores_scan_test.dart`.
const kFunctionsRegion = 'southamerica-east1';

/// Manda TODOS los servicios de Firebase al emulador local
/// (`./scripts/emulator.sh`). La llaman los dos entry points cuando corren con
/// `--dart-define=USE_EMULATOR=true`, después de `Firebase.initializeApp` y
/// antes de cualquier lectura o escritura.
///
/// Es UNA función a propósito. Hasta el 2026-10-14 cada entry point conectaba
/// los emuladores a mano y se desincronizaron: el Coach Hub no redirigía
/// Functions —sus callables (`acceptTrainerLink`, `createPreapproval`, …)
/// pegaban a PRODUCCIÓN— y ninguna de las dos superficies redirigía Storage,
/// así que las subidas iban al bucket real. Un servicio nuevo va acá, una vez.
///
/// Si un emulador no está levantado, ese servicio FALLA en local en vez de
/// salir a producción. Es lo que tiene que pasar.
Future<void> conectarEmuladores() async {
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFunctions.instanceFor(region: kFunctionsRegion)
      .useFunctionsEmulator('localhost', 5001);
  await FirebaseStorage.instance
      .useStorageEmulator('localhost', kPuertoEmuladorStorage);
}
