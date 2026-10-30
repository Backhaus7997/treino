import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../../workout/application/custom_exercise_providers.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/plan_draft_matcher.dart';
import '../data/plan_pdf_import_service.dart';
import 'cf_providers.dart';

final planPdfImportServiceProvider = Provider<PlanPdfImportService>((ref) {
  return PlanPdfImportService(
    call: parsePlanPdfCallable(ref.watch(cloudFunctionsProvider)),
    matcher: PlanDraftMatcher(
      exerciseRepository: ref.watch(exerciseRepositoryProvider),
      // Mismo criterio que el import de Excel: si los propios tardan, se
      // matchea sólo con la biblioteca.
      customExercises: () async {
        final uid = ref.read(currentUidProvider);
        if (uid == null || uid.isEmpty) return const [];
        return ref
            .read(customExercisesForTrainerStreamProvider(uid).future)
            .timeout(const Duration(seconds: 5));
      },
    ),
  );
});

/// Borra la copia del archivo que `file_picker` deja en la caché de la app
/// al elegir (en Android e iOS copia el PDF ahí). El PDF del plan puede traer
/// datos del alumno, y la spec promete que no se guarda: no tiene que quedar
/// en el dispositivo después de procesarlo. En un provider para poder
/// probarlo con un doble.
final pdfPickerCacheCleanerProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await FilePicker.platform.clearTemporaryFiles();
  },
);

/// Si el CTA «Importar de PDF» se muestra. Tres estados, sin colapsar «no
/// sé» con «no hay»: mientras se resuelve la sesión o el documento es
/// [loading], no [disabled].
enum PdfImportGate { loading, enabled, disabled }

/// `app_config/pdf_import` habilita a [uid] si `enabled == true` (booleano) o
/// si [uid] está en `allowlistUids`, igual que `readConfig` del callable.
/// Documento ausente ⇒ apagado: falla cerrado, como el servidor.
bool pdfImportEnabledFor(Map<String, dynamic>? data, String uid) {
  if (data == null) return false;
  if (data['enabled'] == true) return true;
  final allowlist = data['allowlistUids'];
  return allowlist is List && allowlist.contains(uid);
}

/// El documento leído para el uid actual. Un error del stream (permission
/// denied, token perdido) se convierte en `false` cuando llegue: si no,
/// Riverpod conservaría el último `true` y el CTA quedaría prendido después
/// de que el equipo apagara el kill switch (mismo motivo que
/// `interruptorDesde` del gate del mail).
final _pdfImportEnabledStreamProvider = StreamProvider<bool>((ref) {
  final uid =
      ref.watch(authStateChangesProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null) return Stream.value(false);
  return ref
      .watch(firestoreProvider)
      .collection('app_config')
      .doc('pdf_import')
      .snapshots()
      .map((snap) => pdfImportEnabledFor(snap.data(), uid))
      .transform(StreamTransformer<bool, bool>.fromHandlers(
        handleError: (error, stackTrace, sink) => sink.add(false),
      ));
});

/// El CTA es comodidad: la barrera es el servidor, que relee el documento en
/// cada llamada. Por eso un error cae en [PdfImportGate.disabled] y no en un
/// estado propio.
final pdfImportGateProvider = Provider<PdfImportGate>((ref) {
  // `isLoading` antes que `hasValue`: al cambiar de uid el stream se
  // reconstruye conservando el valor ANTERIOR, que es el de otra cuenta.
  final auth = ref.watch(authStateChangesProvider);
  if (auth.isLoading) return PdfImportGate.loading;
  if (auth.hasError) return PdfImportGate.disabled;
  final enabled = ref.watch(_pdfImportEnabledStreamProvider);
  if (enabled.isLoading) return PdfImportGate.loading;
  if (enabled.hasError || !enabled.hasValue) return PdfImportGate.disabled;
  return enabled.requireValue ? PdfImportGate.enabled : PdfImportGate.disabled;
});
