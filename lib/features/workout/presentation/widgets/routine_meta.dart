import '../../../../l10n/app_l10n.dart';
import '../../../profile/domain/experience_level.dart';
import '../../domain/routine.dart';
import '../../domain/routine_day_duration.dart';

/// Los datos con los que un atleta EVALÚA una rutina, en orden de utilidad.
///
/// Vive acá y no adentro de una tarjeta porque lo comparten las dos que
/// muestran rutinas —`RoutineCard` (grilla de EXPLORAR) y la de TU ENTRENO en
/// `rutinas_section.dart`— y tenerlo duplicado es justamente lo que las dejó
/// divergir: #639 rehizo la línea de una y la otra siguió liderando con el
/// `split` en mayúsculas (`'PPL · PRINCIPIANTE'`).
///
/// El orden no es cosmético. Sale de las 5 entrevistas de la auditoría: la
/// gente no elige por *split*, elige por **cuánto puede darle**. Nivel primero
/// (¿es para mí?), después días por semana y minutos por sesión (¿me entra en
/// la semana?).
///
/// El `split` NO está, y esa es la decisión de #648: una persona que nunca pisó
/// un gimnasio no sabe qué es un *Bro Split* — no le cuesta, **no le significa
/// nada** — y era la etiqueta más prominente de la pantalla que tiene que usar
/// para elegir. No se esconde: sigue en el hero del detalle, donde el resumen
/// en criollo que trajo #672 lo explica en el mismo scroll.
List<String> routineMetaSegments(Routine routine, AppL10n l10n) {
  final segments = <String>[routine.level.displayNameEs];

  // Una rutina sin días es un documento válido pero degenerado (spec
  // SCENARIO-052; el detalle tiene su propio empty state). "0 días/sem" sería
  // ruido, así que el segmento se cae — misma regla que la duración de abajo.
  if (routine.days.isNotEmpty) {
    segments.add(l10n.routineCardDaysPerWeek(routine.days.length));
  }

  // La duración se omite ENTERA cuando no hay nada medible — nunca "0 min" ni
  // un guion. Las rutinas publicadas por PFs y por la comunidad no tienen dato
  // garantizado, así que un placeholder sería ruido justo en la parte del
  // catálogo que crece.
  final duration = estimateRoutineSessionMinutes(routine);
  final minutes = duration.minutes;
  if (minutes != null) {
    // "~" marca estimación calculada, misma convención que el tile MINUTOS del
    // detalle (ver RoutineDayDuration).
    segments.add(
      l10n.routineCardMinutes(duration.authored ? '$minutes' : '~$minutes'),
    );
  }

  return segments;
}
