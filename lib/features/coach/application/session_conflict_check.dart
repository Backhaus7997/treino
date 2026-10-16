import '../data/appointment_repository.dart';
import '../data/availability_repository.dart';
import '../domain/appointment.dart';
import '../domain/availability_override.dart';
import '../domain/availability_rule.dart';
import '../domain/session_conflicts.dart';

/// Lee la agenda del PF y chequea si una sesión (o una serie) que está por
/// agendar choca con algo (#1493). Compartido por `new_session_sheet.dart`
/// (mobile) y `new_session_dialog.dart` (web).
///
/// **Falla abierto**, igual que el aviso de día bloqueado: esto es un aviso,
/// no un freno. Si una lectura falla, tarda más de [_kReadTimeout] o el repo no
/// responde, esa fuente se trata como "sin datos" y la sesión se agenda sin el
/// aviso correspondiente. La excepción NO puede escapar: reventaría el
/// `onPressed` async del botón y el tap quedaría mudo.
///
/// Las tres lecturas son one-shot (`.first`) contra el repo y no contra un
/// provider `autoDispose`: nada mantiene vivo un provider para un valor que se
/// necesita una sola vez, justo antes de escribir.
Future<SessionConflicts> checkSessionConflicts({
  required AppointmentRepository appointments,
  required AvailabilityRepository availability,
  required String trainerId,
  required DateTime startsAt,
  required int durationMin,
}) async {
  final agenda = await _readAgenda(
    appointments: appointments,
    availability: availability,
    trainerId: trainerId,
    startsAts: [startsAt],
    durationMin: durationMin,
  );
  return detectSessionConflicts(
    startsAt: startsAt,
    durationMin: durationMin,
    existing: agenda.existing,
    rules: agenda.rules,
    overrides: agenda.overrides,
  );
}

/// [checkSessionConflicts] para una serie: UNA sola lectura que cubre todas
/// las fechas de [startsAts].
Future<SeriesConflicts> checkSeriesConflicts({
  required AppointmentRepository appointments,
  required AvailabilityRepository availability,
  required String trainerId,
  required List<DateTime> startsAts,
  required int durationMin,
}) async {
  if (startsAts.isEmpty) return const SeriesConflicts();
  final agenda = await _readAgenda(
    appointments: appointments,
    availability: availability,
    trainerId: trainerId,
    startsAts: startsAts,
    durationMin: durationMin,
  );
  return detectSeriesConflicts(
    startsAts: startsAts,
    durationMin: durationMin,
    existing: agenda.existing,
    rules: agenda.rules,
    overrides: agenda.overrides,
  );
}

const _kReadTimeout = Duration(seconds: 5);

typedef _Agenda = ({
  List<Appointment> existing,
  List<AvailabilityRule> rules,
  List<AvailabilityOverride> overrides,
});

Future<_Agenda> _readAgenda({
  required AppointmentRepository appointments,
  required AvailabilityRepository availability,
  required String trainerId,
  required List<DateTime> startsAts,
  required int durationMin,
}) async {
  final sorted = [...startsAts]..sort();
  // ±1 día: las sesiones de ayer/mañana pueden cruzar la medianoche.
  final from = sorted.first.subtract(const Duration(days: 1));
  final to = sorted.last.add(Duration(days: 1, minutes: durationMin));

  final results = await Future.wait<Object?>([
    _safe(
      () => appointments
          .watchForTrainer(trainerId, fromDate: from, toDate: to)
          .first,
    ),
    _safe(() => availability.watchRules(trainerId).first),
    _safe(() => availability.watchOverrides(trainerId, from, to).first),
  ]);

  final existing = results[0] as List<Appointment>?;
  final rules = results[1] as List<AvailabilityRule>?;
  final overrides = results[2] as List<AvailabilityOverride>?;

  // Reglas y overrides se miran JUNTOS: con las reglas caídas pero una ventana
  // `extra` leída, "disponibilidad publicada" daría un falso positivo en cada
  // sesión. Si falta una de las dos, la disponibilidad no se chequea.
  final availabilityKnown = rules != null && overrides != null;
  return (
    existing: existing ?? const <Appointment>[],
    rules: availabilityKnown ? rules : const <AvailabilityRule>[],
    overrides: availabilityKnown ? overrides : const <AvailabilityOverride>[],
  );
}

/// Corre [read] y devuelve `null` si tira (incluido un `Fake`/`Mock` sin
/// implementar) o tarda más de [_kReadTimeout].
Future<T?> _safe<T>(Future<T> Function() read) async {
  try {
    return await read().timeout(_kReadTimeout);
  } catch (_) {
    return null;
  }
}
