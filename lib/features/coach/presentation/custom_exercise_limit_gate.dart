import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart'
    show userProfileProvider, userRepositoryProvider;
import '../../profile/domain/user_role.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/custom_exercise_quota_provider.dart';
import 'widgets/custom_exercise_limit_notice.dart';

/// El `kind` que anota [registrarTopeDelPlanPf] cuando el PF choca el tope de
/// ejercicios propios (docs/limite-ejercicios-pf.md §2). Constante
/// compartida entre este embudo y el mail (PR4,
/// `functions/src/subscriptions/trainer-limit-mail.ts`) para que las dos
/// puntas no escriban/lean un literal distinto.
const String kTrainerLimitHitKindCustomExercises = 'customExercises';

/// El embudo único por el que pasan los CINCO puntos de entrada de "crear
/// ejercicio propio" (docs/limite-ejercicios-pf.md, PR3 — "Los cinco puntos
/// de entrada"): "Mis ejercicios" en el móvil, el picker del PF, el
/// onboarding de ejercicios, el editor de rutinas web y el picker web.
/// Mismo criterio que los ocho llamadores de `showFreePlanLimitSheet`: una
/// sola decisión, en un solo lugar.
///
/// Devuelve `true` si el create puede seguir, `false` si el PF ya está en
/// el tope o por encima (E3 — bajar de plan congela la creación, no borra
/// nada).
///
/// ## El alumno nunca se bloquea
///
/// Se corta por ROL **antes** de mirar la cuota, no después: el editor de
/// ejercicios es compartido entre PF y alumno (docs/limite-ejercicios-pf.md,
/// "Qué NO se limita"), y el tope es exclusivamente del PF (E4, mismo
/// criterio que `resolveAthletePaywallEnforced`). Cortar primero por rol
/// hace estructuralmente imposible que un reordenamiento futuro de los `if`
/// termine bloqueando a un alumno.
///
/// ## Qué hace mientras el rol o la cuota todavía no resolvieron
///
/// Deja pasar (fail-open). Sin rol conocido no se puede afirmar "es PF", y
/// [customExerciseQuotaProvider] ya documenta su propio fail-open mientras
/// carga. El servidor manda: un create que no correspondía rebota con
/// `permission-denied` en la regla `customExerciseQuotaOk`, y ese rebote
/// —no este gate— es la red de verdad (ver "El rebote del servidor",
/// docs/limite-ejercicios-pf.md PR3).
///
/// ## El aviso visual
///
/// Sheet de sólo-estado en el móvil, diálogo con VER PLANES en la web
/// (docs/limite-ejercicios-pf.md PR3, "Los avisos") — resuelto por
/// [showCustomExerciseLimitNotice], que decide la superficie con `kIsWeb`
/// (mismo seam de test que `plan_limit_paywall.dart`). Mismo patrón que
/// `showFreePlanLimitSheet`: anotar el tope SIN esperar, apenas se sabe que
/// se chocó; mostrar el aviso después.
Future<bool> intentarCrearEjercicioPropio(
  BuildContext context,
  WidgetRef ref,
) async {
  final role = ref.read(userProfileProvider).valueOrNull?.role;
  if (role != UserRole.trainer) return true;

  final quota = ref.read(customExerciseQuotaProvider).valueOrNull;
  if (quota == null || !quota.isAtOrOverLimit) return true;

  _anotarTopeDelPlan(ref);

  if (context.mounted) {
    // `quota.limit` no puede ser `null` acá: `isAtOrOverLimit` ya lo exige
    // (ver su dartdoc en custom_exercise_quota_provider.dart).
    unawaited(
      showCustomExerciseLimitNotice(
        context,
        limit: quota.limit!,
        count: quota.count,
      ),
    );
  }

  return false;
}

/// Anota que este PF chocó el tope. Lo lee el barrido nocturno del PR4 para
/// mandarle un mail contándole dónde se paga — la app no puede decírselo
/// desde adentro del binario (misma Guideline 3.1.3(f) que documenta
/// `registrarTopeTocado`).
///
/// La llaman los DOS caminos que muestran el aviso: el embudo y el rebote del
/// servidor. Si el rebote no anotara, el PF que choca el tope con la cuota
/// local atrasada (otro dispositivo, caché fría) vería el aviso y nunca
/// recibiría el mail — y en el móvil el mail es su única salida.
///
/// Sin `await` a propósito, mismo motivo que `showFreePlanLimitSheet`: el
/// aviso se muestra ya, no espera a una anotación.
void _anotarTopeDelPlan(WidgetRef ref) {
  // ⚠️ El `try` de acá NO es redundante con el que ya tiene
  // `registrarTopeDelPlanPf` adentro — mismo motivo que documenta
  // `showFreePlanLimitSheet`: aquél cubre el fallo ASÍNCRONO de Firestore,
  // pero cualquier cosa que tire ANTES de entrar al método (un
  // `userRepositoryProvider` overrideado con un doble que tira SÍNCRONO en
  // el test, o un refactor futuro que le saque su propio catch) explota acá
  // y se lleva puesto el `return false` — el PF se quedaría sin el aviso
  // que le explica por qué no puede crear.
  try {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      unawaited(
        ref
            .read(userRepositoryProvider)
            .registrarTopeDelPlanPf(uid, kTrainerLimitHitKindCustomExercises)
            .catchError((_) {}),
      );
    }
  } catch (_) {
    // Ver arriba: el aviso se muestra igual.
  }
}

/// El rebote del servidor (docs/limite-ejercicios-pf.md PR3, "El rebote del
/// servidor"): un `permission-denied` en el CREATE de un PF —el contador se
/// adelantó, o hubo una carrera— muestra el MISMO aviso que
/// [intentarCrearEjercicioPropio], no el error genérico.
///
/// Devuelve `true` si mostró el aviso — el call site no debe mostrar
/// TAMBIÉN su mensaje genérico. Devuelve `false` cuando la cuota todavía no
/// resolvió un límite concreto: sin un número real, el aviso inventaría un
/// dato que el servidor no confirmó (AGENTS.md §11.1 — una advertencia que
/// miente es peor que ninguna), así que el call site cae a su mensaje
/// genérico existente.
Future<bool> mostrarAvisoTopeEjerciciosPorRebote(
  BuildContext context,
  WidgetRef ref,
) async {
  // El servidor ya dijo que no: se anota aunque la cuota local todavía no
  // tenga un número. El barrido del mail vuelve a mirar `planLimits` y
  // `customExerciseUsage` antes de mandar nada, así que una anotación de más
  // no llega a ningún buzón.
  final role = ref.read(userProfileProvider).valueOrNull?.role;
  if (role == UserRole.trainer) _anotarTopeDelPlan(ref);

  final quota = ref.read(customExerciseQuotaProvider).valueOrNull;
  final limit = quota?.limit;
  if (limit == null || !context.mounted) return false;
  await showCustomExerciseLimitNotice(context,
      limit: limit, count: quota!.count);
  return true;
}
