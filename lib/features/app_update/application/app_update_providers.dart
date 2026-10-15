import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../profile/application/user_providers.dart';
import '../domain/min_version_config.dart';

/// Cuánto esperamos al documento antes de rendirnos y dejar pasar.
const Duration kMinVersionTimeout = Duration(seconds: 5);

/// Plataforma que el gate evalúa. `null` en web (el Coach Hub NUNCA se gatea:
/// se despliega con cada release, no hay versión vieja instalada) y en
/// cualquier otro target. Los relojes tienen su propio entrypoint
/// (`main_wear.dart`) y nunca montan `TreinoApp`.
final appUpdatePlatformProvider = Provider<AppUpdatePlatform?>((ref) {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return AppUpdatePlatform.ios;
    case TargetPlatform.android:
      return AppUpdatePlatform.android;
    default:
      return null;
  }
});

/// `PackageInfo.version` (`versionName` en Android, `CFBundleShortVersionString`
/// en iOS; sin el build number). `null` si el plugin falla.
final installedVersionProvider = FutureProvider<String?>((ref) async {
  try {
    return (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    return null;
  }
});

/// Lee `app_config/min_version` UNA vez por arranque.
///
/// FALLA ABIERTO. Cualquier cosa que no sea un documento legible —sin red,
/// timeout, permission-denied, documento ausente, malformado— devuelve `null`
/// y la app arranca normal. La razón es de producto: este gate es una
/// herramienta para evitar daño de datos, no un control de acceso. Una caída
/// de red o un error nuestro en el documento no puede dejar a TODOS los
/// usuarios mirando un cartel de «actualizá» (y peor: sin poder hacerlo si la
/// tienda ya no tiene una versión más nueva). Quedarse en una versión vieja
/// durante un arranque sin conexión es el mal menor.
///
/// Sin conexión, Firestore puede entregar la copia en caché del último
/// arranque: es válido (el mínimo solo sube).
///
/// No lee nada en web ni en plataformas sin gate.
final minVersionConfigProvider = FutureProvider<MinVersionConfig?>((ref) async {
  if (ref.watch(appUpdatePlatformProvider) == null) return null;
  try {
    // Dentro del try: un Firebase sin inicializar también tiene que fallar
    // abierto.
    final FirebaseFirestore firestore = ref.watch(firestoreProvider);
    final snap = await firestore
        .collection('app_config')
        .doc('min_version')
        .get()
        .timeout(kMinVersionTimeout);
    return MinVersionConfig.fromMap(snap.data());
  } catch (_) {
    return null;
  }
});

/// `null` mientras carga, ante error, o si la versión instalada alcanza.
/// Solo un valor no-nulo bloquea la app.
final updateRequirementProvider = Provider<UpdateRequirement?>((ref) {
  return UpdateRequirement.evaluar(
    platform: ref.watch(appUpdatePlatformProvider),
    installedVersion: ref.watch(installedVersionProvider).valueOrNull,
    config: ref.watch(minVersionConfigProvider).valueOrNull,
  );
});
