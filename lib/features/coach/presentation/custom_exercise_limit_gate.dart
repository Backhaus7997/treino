import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart'
    show userProfileProvider, userRepositoryProvider;
import '../../profile/domain/user_role.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'custom_exercise_quota_provider.dart';

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
/// ## TODO(entrypoints)
///
/// El aviso visual real —sheet de sólo-estado en el móvil, diálogo con VER
/// PLANES en la web (docs/limite-ejercicios-pf.md PR3, "Los avisos")— lo
/// completa el tramo que cablea los cinco puntos de entrada. Esta pieza
/// fundacional deja el punto de enganche marcado en
/// [_mostrarAvisoTopeEjerciciosPropios]: mismo patrón que
/// `showFreePlanLimitSheet` (anotar el tope SIN esperar, apenas se sabe que
/// se chocó; mostrar el aviso después). A diferencia de aquella, acá la
/// SUPERFICIE (móvil vs. web) decide qué mostrar — la firma de esta función
/// no cambia para resolverlo: el siguiente tramo puede ramificar adentro de
/// [_mostrarAvisoTopeEjerciciosPropios] (por ejemplo con `kIsWeb`, o con lo
/// que use el resto del Coach Hub para distinguir superficie) sin tocar a
/// ningún llamador de [intentarCrearEjercicioPropio].
Future<bool> intentarCrearEjercicioPropio(
  BuildContext context,
  WidgetRef ref,
) async {
  final role = ref.read(userProfileProvider).valueOrNull?.role;
  if (role != UserRole.trainer) return true;

  final quota = ref.read(customExerciseQuotaProvider).valueOrNull;
  if (quota == null || !quota.isAtOrOverLimit) return true;

  // Se anota que este PF chocó el tope. Lo lee el barrido nocturno del PR4
  // para mandarle un mail contándole dónde se paga — la app no puede
  // decírselo desde adentro del binario (misma Guideline 3.1.3(f) que
  // documenta `registrarTopeTocado`).
  //
  // Sin `await` a propósito, mismo motivo que `showFreePlanLimitSheet`: el
  // aviso se muestra ya, no espera a una anotación.
  //
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

  if (context.mounted) {
    _mostrarAvisoTopeEjerciciosPropios(context);
  }

  return false;
}

/// Punto de enganche para el aviso visual real.
///
/// TODO(entrypoints): hoy es un no-op intencional. El tramo que cablea los
/// cinco puntos de entrada (docs/limite-ejercicios-pf.md PR3) lo reemplaza
/// por el sheet de sólo-estado en el móvil (sin botón, sin "web", sin
/// "pasá a un plan" — `anti_steering_movil_test.dart` y
/// `superficie_de_cobro_alumno_test.dart` lo cuidan) y por el diálogo con
/// VER PLANES en la web.
void _mostrarAvisoTopeEjerciciosPropios(BuildContext context) {
  // Intencionalmente vacío — ver el TODO de arriba.
}
