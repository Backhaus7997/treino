// Mutaciones de rutinas para el Coach Hub web: archivar, recuperar, ELIMINAR,
// asignar, publicar/despublicar, y publicar como plantilla el plan de un
// alumno.
//
// Todas invalidan `routinesAuthoredByProvider`, que es de donde lee la
// pantalla de Rutinas desde que pasó a listar rutinas en vez de alumnos.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show invalidateRoutineById, routineRepositoryProvider;

/// Notifier sin estado propio relevante para la UI: la fila que dispara la
/// acción mantiene su propio flag de "busy" local (mismo criterio que el
/// resto del Coach Hub web, ver `alumnos_screen.dart._confirmAction` +
/// llamada posterior). Este provider sólo centraliza la llamada al repo + la
/// invalidación del listado afectado, para que sea testeable sin montar
/// widgets.
class RoutineActionsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Archiva [routineId] (soft-delete, ADR-USR-04) e invalida
  /// [assignedRoutinesByTrainerProvider] del par [trainerId]/[athleteId] para
  /// que la fila desaparezca de "Activas" en el próximo fetch, más las cachés
  /// single-doc de la rutina vía [invalidateRoutineById].
  ///
  /// ⚠️  [trainerId] NO es decorativo: es parte de la CLAVE del provider. El
  /// listado del Coach Hub se mudó a `assignedRoutinesByTrainerProvider`
  /// porque el `list` del PF necesita `assignedBy` en la query para que las
  /// reglas lo puedan probar. Si esta invalidación siguiera pegándole a
  /// `assignedRoutinesProvider(athleteId)` —la clave VIEJA— la llamada no
  /// fallaría ni compilaría mal: simplemente invalidaría un provider que ya
  /// nadie mira, y la rutina archivada seguiría en pantalla hasta recargar.
  /// Un fallo silencioso, que es justo lo que AGENTS.md §11.1 prohíbe.
  ///
  /// Devuelve `true` en éxito, `false` si el repo tira una excepción — la UI
  /// decide cómo comunicar el error (snackbar).
  Future<bool> archive({
    required String routineId,
    required String trainerId,
    required String athleteId,
  }) async =>
      _flipStatus(
        routineId: routineId,
        trainerId: trainerId,
        athleteId: athleteId,
        escribir: (repo) => repo.archive(routineId),
      );

  /// El camino de vuelta: devuelve la rutina archivada a `active`.
  ///
  /// Va junto a [archive] y con las MISMAS invalidaciones, no porque sea
  /// simétrico en la UI —la card aparece en un filtro y desaparece del otro—
  /// sino porque el fallo es simétrico: si sólo se invalidara la grilla, la
  /// rutina recuperada no volvería a la ficha del alumno hasta recargar.
  ///
  /// Sin esto, el diálogo de archivar prometía algo que el producto no podía
  /// cumplir. El filtro «Archivadas» la muestra; recuperarla no existía.
  Future<bool> unarchive({
    required String routineId,
    required String trainerId,
    required String athleteId,
  }) async =>
      _flipStatus(
        routineId: routineId,
        trainerId: trainerId,
        athleteId: athleteId,
        escribir: (repo) => repo.unarchive(routineId),
      );

  /// Lo común de [archive] y [unarchive]: escribir y después invalidar TODO lo
  /// que mira ese documento.
  ///
  /// Está factorizado a propósito y no duplicado. Las tres invalidaciones son
  /// la parte fácil de olvidar y la que no falla ruidosamente: olvidar una no
  /// rompe la compilación ni tira excepción, sólo deja una card vieja en
  /// pantalla hasta recargar. Con dos copias, el próximo que agregue un cuarto
  /// lector actualiza una y no la otra.
  Future<bool> _flipStatus({
    required String routineId,
    required String trainerId,
    required String athleteId,
    required Future<void> Function(RoutineRepository repo) escribir,
  }) async {
    try {
      await escribir(ref.read(routineRepositoryProvider));
      ref.invalidate(assignedRoutinesByTrainerProvider(
        (trainerId: trainerId, athleteId: athleteId),
      ));
      // Y la grilla de la sección Rutinas, que lee de OTRO provider desde que
      // el eje pasó a ser el autor. Sin esta línea la card archivada seguiría
      // en pantalla hasta recargar — el mismo fallo silencioso que describe la
      // advertencia de arriba, una mudanza de provider más tarde.
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      // El listado no alcanza: los lectores one-shot de la rutina archivada
      // (`routineByIdProvider` / `visibleRoutineByIdProvider`) siguen
      // devolviendo el doc con `status: active` hasta que se reinicie el
      // proceso. `ref.container` porque el notifier no es un widget.
      invalidateRoutineById(ref.container, routineId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// BORRA [routineId] de verdad. Irreversible.
  ///
  /// Convive con [archive] a propósito, no la reemplaza. La app archiva por
  /// defecto —«el documento se conserva para mantener referencias históricas
  /// de sesiones», ADR-USR-04— y eso sigue siendo lo correcto para un plan que
  /// alguien entrenó: las sesiones apuntan al doc, y borrarlo las deja sin
  /// referencia.
  ///
  /// Eliminar es para lo otro: una plantilla que nunca se entrenó, o un plan
  /// que se cargó mal y no debería figurar en la biblioteca. Quién ofrece cuál
  /// —y con qué advertencia— lo decide la UI, que es la que sabe si la rutina
  /// tiene alumno.
  ///
  /// Las reglas de Firestore ya restringen el borrado al dueño
  /// (`assignedBy == request.auth.uid`); esto no afloja nada.
  Future<bool> delete({
    required String routineId,
    required String trainerId,
  }) async {
    try {
      await ref.read(routineRepositoryProvider).deleteRoutine(routineId);
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      invalidateRoutineById(ref.container, routineId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asigna [template] a [athleteId]. Devuelve `true` en éxito.
  ///
  /// **COPIA, no mueve.** `assignTemplateToAthlete` crea un documento NUEVO
  /// —`source: trainer-assigned`, `visibility: private`— y la plantilla queda
  /// donde estaba. Es a propósito: la plantilla es reutilizable, y si asignarla
  /// la consumiera no se podría dar la misma rutina a dos alumnos.
  ///
  /// Por eso la card de la plantilla NO cambia de estado al asignar, y la UI
  /// tiene que decirlo — si no, el PF asigna, no ve nada distinto y vuelve a
  /// apretar.
  ///
  /// Se invalidan los DOS listados: el de la sección (por el doc nuevo) y el
  /// del par trainer/alumno, que es de donde lee la ficha del alumno.
  Future<bool> assignTemplate({
    required Routine template,
    required String athleteId,
    required String trainerId,
  }) async {
    try {
      await ref.read(routineRepositoryProvider).assignTemplateToAthlete(
            template: template,
            athleteId: athleteId,
          );
      // `routine_created` va acá igual que en el gemelo de mobile
      // (`trainer_workout_view.dart`, que ya lo emitía con el mismo `source`):
      // `assignTemplateToAthlete` CREA un documento, y el dartdoc del evento
      // dice que las del PF se cuentan igual porque «omitirlas dejaría el
      // evento ciego a la mitad de las rutinas». Faltaba sólo del lado web, así
      // que las asignaciones hechas desde el Coach Hub desaparecían de la
      // medición mientras las del teléfono se contaban — el peor caso para un
      // número que se compara entre superficies.
      //
      // `trainerAssigned` y no `trainerTemplate`: lo que se escribió es la
      // copia del alumno. La plantilla no se toca.
      unawaited(ref.read(analyticsServiceProvider).logRoutineCreated(
            source: RoutineCreationSource.trainerAssigned,
            daysCount: template.days.length,
            weeksCount: template.numWeeks,
          ));
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      ref.invalidate(assignedRoutinesByTrainerProvider(
        (trainerId: trainerId, athleteId: athleteId),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Publica el plan de un alumno COMO PLANTILLA: crea una plantilla nueva a
  /// partir de él y publica ESA. El plan del alumno no se toca.
  ///
  /// La regla de Firestore restringe el flip de `visibility` a docs
  /// `trainer-template` (UPDATE path 5), así que publicar la copia de un
  /// alumno está denegado por contrato — y con razón: esa copia lleva su
  /// nombre y su historial. Esto es la forma correcta de lo que el PF pidió
  /// («esté asignada o no la rutina, poder publicarla»).
  ///
  /// [nombre] lo elige el PF en el diálogo y NO se deriva del plan. Publicar
  /// expone el nombre al catálogo de la comunidad, y un plan asignado suele
  /// llamarse por su dueño («Plan de Sofía»): heredarlo en silencio filtraría
  /// el nombre de una clienta. Es la diferencia con «Guardar como copia» del
  /// editor, donde la copia es privada y el nombre va automático.
  ///
  /// Devuelve un [ResultadoDePublicar] y no un `bool` porque son DOS
  /// escrituras y el medio importa: si la plantilla se creó y el publish
  /// falla, un `false` haría que el PF reintente y termine con dos
  /// plantillas. La UI tiene que poder decir «se creó pero no se publicó».
  Future<ResultadoDePublicar> publicarComoPlantilla({
    required Routine plan,
    required String nombre,
    required String trainerId,
  }) async {
    final Routine creada;
    try {
      creada = await ref.read(routineRepositoryProvider).createTemplate(
            plan.copyWith(
              id: '',
              name: nombre,
              source: RoutineSource.trainerTemplate,
              assignedBy: trainerId,
              assignedTo: null,
              visibility: RoutineVisibility.private,
              // Los agregados de la comunidad son del documento publicado, no
              // del plan del que se copió. Mismo criterio que
              // `assignTemplateToAthlete`: `toJson()` ya los excluye del
              // write, y limpiarlos acá mantiene fiel al objeto devuelto.
              ratingAvg: null,
              ratingsCount: null,
            ),
          );
    } catch (_) {
      return ResultadoDePublicar.falloAlCrear;
    }

    // El evento va acá y NO después del publish, por el mismo motivo que la
    // invalidación: la rutina se creó. El dartdoc de `logRoutineCreated` es
    // explícito en que las del PF se cuentan igual —«omitirlas dejaría el
    // evento ciego a la mitad de las rutinas y sesgaría la comparación»—, así
    // que una plantilla que existe pero no se llegó a publicar tiene que
    // contarse lo mismo.
    //
    // `trainerTemplate` y no `trainerAssigned`: lo que se acaba de escribir es
    // una plantilla, aunque se haya llegado acá desde el plan de un alumno. Es
    // la misma trampa que #1097 corrigió en el editor — el evento describe la
    // ESCRITURA, no la pantalla desde la que se disparó.
    unawaited(ref.read(analyticsServiceProvider).logRoutineCreated(
          source: RoutineCreationSource.trainerTemplate,
          daysCount: creada.days.length,
          weeksCount: creada.numWeeks,
        ));

    // La grilla ya tiene que enterarse de la plantilla nueva aunque el publish
    // falle: existe igual, y si no aparece el PF no tiene cómo publicarla a
    // mano ni cómo evitar crear otra.
    ref.invalidate(routinesAuthoredByProvider(trainerId));

    try {
      await ref.read(routineRepositoryProvider).publishTemplate(creada.id);
    } catch (_) {
      return ResultadoDePublicar.creadaPeroSinPublicar;
    }

    ref.invalidate(routinesAuthoredByProvider(trainerId));
    invalidateRoutineById(ref.container, creada.id);
    return ResultadoDePublicar.ok;
  }

  /// Pone [routineId] pública o privada.
  ///
  /// Sólo vale sobre PLANTILLAS: la regla de Firestore restringe el flip a
  /// docs `trainer-template` del dueño. Ofrecerlo sobre una rutina asignada
  /// sería un botón que falla siempre, así que quien arma el menú tiene que
  /// gatearlo — acá se asume ya gateado.
  ///
  /// Despublicar NO borra las valoraciones de la comunidad: quedan en la
  /// subcolección y vuelven intactas si se republica.
  Future<bool> setPublicada({
    required String routineId,
    required bool publicada,
    required String trainerId,
  }) async {
    try {
      final repo = ref.read(routineRepositoryProvider);
      await (publicada
          ? repo.publishTemplate(routineId)
          : repo.unpublishTemplate(routineId));
      ref.invalidate(routinesAuthoredByProvider(trainerId));
      invalidateRoutineById(ref.container, routineId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final routineActionsProvider =
    AsyncNotifierProvider<RoutineActionsNotifier, void>(
  RoutineActionsNotifier.new,
);

/// Cómo terminó [RoutineActionsNotifier.publicarComoPlantilla].
///
/// Tres estados y no dos, porque son dos escrituras: el del medio existe de
/// verdad y esconderlo detrás de un `false` hace que el PF reintente sobre una
/// plantilla que YA se creó.
enum ResultadoDePublicar {
  /// Se creó la plantilla y quedó pública.
  ok,

  /// No se pudo crear. No quedó nada.
  falloAlCrear,

  /// La plantilla se creó pero sigue privada. Está en la biblioteca del PF y
  /// se publica desde su propio menú — reintentar acá crearía una segunda.
  creadaPeroSinPublicar,
}
