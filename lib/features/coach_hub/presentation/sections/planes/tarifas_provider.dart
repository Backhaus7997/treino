import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../payments/domain/athlete_billing.dart';
import '../../../../profile/application/user_providers.dart'
    show firestoreProvider;
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'tarifas_model.dart';

/// Stream de TODOS los [AthleteBilling] del PF actual (uno por alumno),
/// leídos directamente de la colección `athlete_billing` filtrando por
/// `trainerId` — a diferencia de `athleteBillingProvider`
/// (`billing_providers.dart`), que lee un doc a la vez por alumno.
///
/// Las reglas de Firestore ya permiten esta query trainer-wide
/// (`allow read if resource.data.trainerId == request.auth.uid` sobre la
/// colección `athlete_billing`). Si en runtime diera permission-denied, el
/// fallback es hacer fanout por `trainerLinksStreamProvider` + un `watch`
/// por alumno (como `pagosPorCobrarProvider`) — no implementado en este WU.
final trainerBillingsProvider =
    StreamProvider.autoDispose<List<AthleteBilling>>((ref) {
  final trainerId = ref.watch(currentUidProvider);
  if (trainerId == null) return Stream.value(const []);

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('athlete_billing')
      .where('trainerId', isEqualTo: trainerId)
      .snapshots()
      .map((snapshot) {
    final result = <AthleteBilling>[];
    for (final doc in snapshot.docs) {
      try {
        result.add(AthleteBilling.fromJson(doc.data()));
      } catch (_) {
        // Doc no parseable — se descarta, igual que
        // BillingRepository._fromDoc (billing_repository.dart).
      }
    }
    return result;
  });
});

/// Resumen agregado de tarifas comerciales del PF, derivado de
/// [trainerBillingsProvider] vía `agruparTarifas` (lógica pura testeable en
/// `tarifas_model.dart`).
///
/// hasValue-first (pulido-post-revision, ROOT-CAUSE, mismo defecto que
/// Chat/Pagos, commits cdd41949/b3a14117): [trainerBillingsProvider] es un
/// `StreamProvider` en vivo — Riverpod 2.5+ preserva el valor previo dentro
/// de un `AsyncError` subsiguiente (`copyWithPrevious`/"seamless"), así que
/// `billingsAsync.hasValue == true` Y `hasError == true` pueden darse a la
/// vez tras un error transitorio del stream. La composición anterior usaba
/// `.whenData()`, que internamente es `.map()` y despacha por el SUBTIPO
/// RUNTIME del AsyncValue (ignora `hasValue`): en ese estado compuesto caía
/// en la rama `error:`, que devuelve `hasValue: false` explícito — TIRABA el
/// resumen ya calculado aunque el stream de tarifas siguiera teniendo el
/// valor cacheado. Se chequea `hasValue` explícitamente ANTES de mirar el
/// error para que un error transitorio nunca tape el resumen ya cargado.
final tarifasResumenProvider =
    Provider.autoDispose<AsyncValue<TarifasResumen>>((ref) {
  final billingsAsync = ref.watch(trainerBillingsProvider);

  if (billingsAsync.hasValue) {
    return AsyncValue.data(agruparTarifas(billingsAsync.requireValue));
  }
  if (billingsAsync.hasError) {
    return AsyncValue<TarifasResumen>.error(
      billingsAsync.error!,
      billingsAsync.stackTrace ?? StackTrace.current,
    );
  }
  return const AsyncValue.loading();
});
