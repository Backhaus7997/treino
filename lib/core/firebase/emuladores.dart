import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
}
