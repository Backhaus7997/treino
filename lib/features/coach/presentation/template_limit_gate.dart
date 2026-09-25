import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart'
    show userProfileProvider, userRepositoryProvider;
import '../../profile/domain/user_role.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/template_quota_provider.dart';
import 'widgets/trainer_limit_notice.dart';

/// El `kind` que anota [registrarTopeDelPlanPf] cuando el PF choca el tope de
/// plantillas (docs/limite-plantillas-pf.md §2). Constante compartida entre
/// este embudo y el mail (PR4, `functions/src/subscriptions/
/// trainer-limit-mail.ts`) para que las dos puntas no escriban/lean un
/// literal distinto.
const String kTrainerLimitHitKindTemplates = 'templates';

/// El embudo único por el que pasan los SIETE puntos de entrada de "crear o
/// restaurar una plantilla" (docs/limite-plantillas-pf.md, PR3 — "Los puntos
/// de entrada"): el CTA del dashboard, el editor web (guardar nueva y
/// "guardar como copia"), "publicar como plantilla" y restaurar una
/// archivada desde la grilla web, y "NUEVA"/guardar nueva plantilla en el
/// móvil. Mismo criterio que [intentarCrearEjercicioPropio]: una sola
/// decisión, en un solo lugar.
///
/// Devuelve `true` si el create/unarchive puede seguir, `false` si el PF ya
/// está en el tope o por encima (P5 — bajar de plan congela la creación, no
/// borra ni desarchiva nada).
///
/// ## El alumno nunca se bloquea
///
/// Se corta por ROL **antes** de mirar la cuota, no después: el CREATE de
/// `routines` no chequea rol (docs/limite-plantillas-pf.md P6), y el tope es
/// exclusivamente del PF. Cortar primero por rol hace estructuralmente
/// imposible que un reordenamiento futuro de los `if` termine bloqueando a
/// un alumno.
///
/// ## Qué hace mientras el rol o la cuota todavía no resolvieron
///
/// Deja pasar (fail-open). Sin rol conocido no se puede afirmar "es PF", y
/// [templateQuotaProvider] ya documenta su propio fail-open mientras carga.
/// El servidor manda: un create o restore que no correspondía rebota con
/// `permission-denied` en la regla `templateQuotaOk`, y ese rebote —no este
/// gate— es la red de verdad (ver "El rebote del servidor",
/// docs/limite-plantillas-pf.md PR3).
///
/// ## El aviso visual
///
/// Sheet de sólo-estado en el móvil, diálogo con VER PLANES en la web
/// (docs/limite-plantillas-pf.md PR3, "Los avisos") — resuelto por
/// [showTrainerLimitNotice], que decide la superficie con `kIsWeb`. Mismo
/// patrón que [intentarCrearEjercicioPropio]: anotar el tope SIN esperar,
/// apenas se sabe que se chocó; mostrar el aviso después.
Future<bool> intentarCrearPlantilla(
  BuildContext context,
  WidgetRef ref,
) async {
  final role = ref.read(userProfileProvider).valueOrNull?.role;
  if (role != UserRole.trainer) return true;

  final quota = ref.read(templateQuotaProvider).valueOrNull;
  if (quota == null || !quota.isAtOrOverLimit) return true;

  _anotarTopeDelPlan(ref);

  if (context.mounted) {
    // `quota.limit` no puede ser `null` acá: `isAtOrOverLimit` ya lo exige
    // (ver su dartdoc en template_quota_provider.dart).
    unawaited(
      showTrainerLimitNotice(
        context,
        kind: TrainerLimitKind.templates,
        limit: quota.limit!,
        count: quota.count,
      ),
    );
  }

  return false;
}

/// Anota que este PF chocó el tope de plantillas. Lo lee el barrido nocturno
/// del PR4 para mandarle un mail contándole dónde se paga — la app no puede
/// decírselo desde adentro del binario (misma Guideline 3.1.3(f) que
/// documenta [intentarCrearEjercicioPropio]).
///
/// La llaman los DOS caminos que muestran el aviso: el embudo y el rebote
/// del servidor. Sin `await` a propósito, mismo motivo que
/// `_anotarTopeDelPlan` de ejercicios propios: el aviso se muestra ya, no
/// espera a una anotación.
void _anotarTopeDelPlan(WidgetRef ref) {
  // ⚠️ El `try` de acá NO es redundante con el que ya tiene
  // `registrarTopeDelPlanPf` adentro — mismo motivo que documenta
  // `intentarCrearEjercicioPropio`: aquél cubre el fallo ASÍNCRONO de
  // Firestore, pero cualquier cosa que tire ANTES de entrar al método explota
  // acá y se lleva puesto el `return false` — el PF se quedaría sin el aviso
  // que le explica por qué no puede crear.
  try {
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      unawaited(
        ref
            .read(userRepositoryProvider)
            .registrarTopeDelPlanPf(uid, kTrainerLimitHitKindTemplates)
            .catchError((_) {}),
      );
    }
  } catch (_) {
    // Ver arriba: el aviso se muestra igual.
  }
}

/// El rebote del servidor (docs/limite-plantillas-pf.md PR3, "El rebote del
/// servidor"): un `permission-denied` en el `createTemplate` o `unarchive` de
/// un PF —el contador se adelantó, o hubo una carrera— muestra el MISMO
/// aviso que [intentarCrearPlantilla], no el error genérico.
///
/// Devuelve `true` si mostró el aviso — el call site no debe mostrar TAMBIÉN
/// su mensaje genérico. Devuelve `false` cuando la cuota todavía no resolvió
/// un límite concreto: sin un número real, el aviso inventaría un dato que
/// el servidor no confirmó (AGENTS.md §11.1), así que el call site cae a su
/// mensaje genérico existente.
Future<bool> mostrarAvisoTopeDePlantillasPorRebote(
  BuildContext context,
  WidgetRef ref,
) async {
  // El servidor ya dijo que no: se anota aunque la cuota local todavía no
  // tenga un número. El barrido del mail vuelve a mirar `planLimits` y
  // `templateUsage` antes de mandar nada, así que una anotación de más no
  // llega a ningún buzón.
  final role = ref.read(userProfileProvider).valueOrNull?.role;
  if (role == UserRole.trainer) _anotarTopeDelPlan(ref);

  final quota = ref.read(templateQuotaProvider).valueOrNull;
  final limit = quota?.limit;
  if (limit == null || !context.mounted) return false;
  await showTrainerLimitNotice(
    context,
    kind: TrainerLimitKind.templates,
    limit: limit,
    count: quota!.count,
  );
  return true;
}
