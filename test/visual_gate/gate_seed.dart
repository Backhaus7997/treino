/// Seed determinístico del gate visual del Coach Hub (#761).
///
/// ## La regla
///
/// **Ningún dato de acá depende del reloj, de la red ni de una cuenta real.**
/// Todas las fechas se derivan de [kGateNow] —el instante que `AppClock`
/// congela— por offsets fijos. Si un golden cambia, cambió el código; nunca el
/// calendario.
///
/// ## Por qué está poblado y no vacío
///
/// Un gate contra estados vacíos cubre el layout de MENOR riesgo: una lista sin
/// filas no desborda, una grilla sin celdas no se descuadra. Las regresiones
/// visuales viven en la pantalla llena. Por eso el seed tiene alumnos con
/// nombres de largos distintos, un pago vencido y uno por vencer, turnos antes
/// y después de la hora congelada, y badges con número.
///
/// ## Nombres
///
/// Largos deliberadamente desparejos: "Ana Ruiz" (8) hasta
/// "Maximiliano Etcheverry Paz" (26). El truncado con elipsis es de los
/// defectos visuales más comunes y sólo aparece si alguien lo provoca.
///
/// Ninguno tiene `avatarUrl`: un avatar remoto en un widget test es una
/// petición HTTP que `flutter_test` responde con 400, y el golden termina
/// fotografiando un placeholder de error. Los avatares del kit caen a
/// iniciales, que es un camino de render real y estable.
library;

import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import 'gate_environment.dart';

/// UID del PF logueado en todos los goldens.
const String kGateTrainerId = 'gate-trainer';

/// Nombre del PF. Aparece en el sidebar y en el top bar de TODA captura, así
/// que un cambio acá mueve los 14 goldens: no lo toques sin querer hacerlo.
const String kGateTrainerName = 'Mateo García';

/// Un alumno del seed. Plano a propósito: lo que el gate necesita de un alumno
/// es su id y cómo se ve su nombre, no un modelo de dominio completo.
class GateAthlete {
  const GateAthlete(this.id, this.name);

  final String id;
  final String name;
}

/// Los seis alumnos del seed, en orden estable.
///
/// Seis y no veinte: alcanzan para llenar una lista, poblar los dos badges del
/// sidebar (Solicitudes y Pagos — el resto no tiene) y disparar el truncado, y
/// caben en una captura sin que haya que scrollear.
const List<GateAthlete> kGateAthletes = [
  GateAthlete('gate-ath-1', 'Ana Ruiz'),
  GateAthlete('gate-ath-2', 'Bruno Sosa'),
  GateAthlete('gate-ath-3', 'Camila Fernández'),
  GateAthlete('gate-ath-4', 'Maximiliano Etcheverry Paz'),
  GateAthlete('gate-ath-5', 'Lucía Ibáñez'),
  GateAthlete('gate-ath-6', 'Tomás Vega'),
];

/// Perfil del PF logueado.
UserProfile gateTrainerProfile() => UserProfile(
      uid: kGateTrainerId,
      email: 'mateo@treino.app',
      displayName: kGateTrainerName,
      role: UserRole.trainer,
      createdAt: DateTime.utc(2025, 9, 1),
      updatedAt: DateTime.utc(2026, 1, 12),
    );

/// Perfil público de un alumno, sin avatar remoto (ver dartdoc de la librería).
UserPublicProfile gateAthleteProfile(GateAthlete athlete) => UserPublicProfile(
      uid: athlete.id,
      displayName: athlete.name,
      displayNameLowercase: athlete.name.toLowerCase(),
    );

/// Vínculos PF ↔ alumno: 4 activos, 1 pendiente, 1 pausado.
///
/// La mezcla no es decorativa: el badge de Solicitudes cuenta `pending`, el
/// dashboard cuenta `active`, y la lista de Alumnos pinta `paused` distinto.
/// Con seis vínculos todos activos, tres de esos caminos no se fotografían.
List<TrainerLink> gateTrainerLinks() {
  final base = kGateNow.toUtc();
  TrainerLink link(
    int index,
    TrainerLinkStatus status, {
    int requestedDaysAgo = 60,
    int? acceptedDaysAgo,
  }) {
    final athlete = kGateAthletes[index];
    return TrainerLink(
      id: 'gate-link-${athlete.id}',
      trainerId: kGateTrainerId,
      athleteId: athlete.id,
      status: status,
      requestedAt: base.subtract(Duration(days: requestedDaysAgo)),
      acceptedAt: acceptedDaysAgo == null
          ? null
          : base.subtract(Duration(days: acceptedDaysAgo)),
      sharedWithTrainer: true,
    );
  }

  return [
    link(0, TrainerLinkStatus.active,
        requestedDaysAgo: 120, acceptedDaysAgo: 119),
    link(1, TrainerLinkStatus.active,
        requestedDaysAgo: 90, acceptedDaysAgo: 88),
    link(2, TrainerLinkStatus.active,
        requestedDaysAgo: 45, acceptedDaysAgo: 44),
    link(3, TrainerLinkStatus.active,
        requestedDaysAgo: 30, acceptedDaysAgo: 30),
    link(4, TrainerLinkStatus.paused,
        requestedDaysAgo: 200, acceptedDaysAgo: 198),
    link(5, TrainerLinkStatus.pending, requestedDaysAgo: 2),
  ];
}

/// Turnos del día congelado: uno ya pasó, dos todavía no.
///
/// `startsAt` es wall-clock ADR-7 (campos locales etiquetados UTC), igual que
/// lo escribe el picker del PF. El turno de las 09:00 queda ANTES de las 10:30
/// congeladas y los otros dos después — así el golden cubre las dos ramas de
/// `startsAt.isAfter(now)` del dashboard, que es exactamente el filtro que
/// volvía flaky a esta pantalla antes del seam de reloj.
List<Appointment> gateAppointments() {
  Appointment at(int index, int hour, int minute, AppointmentStatus status) {
    final athlete = kGateAthletes[index];
    return Appointment(
      id: 'gate-appt-$hour$minute',
      trainerId: kGateTrainerId,
      athleteId: athlete.id,
      athleteDisplayName: athlete.name,
      startsAt: DateTime.utc(
        kGateNow.year,
        kGateNow.month,
        kGateNow.day,
        hour,
        minute,
      ),
      durationMin: 60,
      status: status,
    );
  }

  return [
    at(0, 9, 0, AppointmentStatus.confirmed),
    at(2, 11, 30, AppointmentStatus.confirmed),
    at(3, 16, 0, AppointmentStatus.confirmed),
  ];
}

/// Pagos del PF: 2 vencidos, 1 por vencer, 3 cobrados.
///
/// Se entregan CRUDOS al `trainerPaymentsProvider`, no bucketeados: así el
/// golden pasa por el `pagosBucketsProvider` real, que clasifica en ART contra
/// el reloj congelado. Stubear los buckets ya hechos saltearía justo la lógica
/// que el gate quiere ver rendida.
///
/// Montos con separador de miles y uno de seis cifras: `fmtArs` agrupa de a
/// tres y ahí es donde se rompe una columna angosta.
List<Payment> gatePayments() {
  final base = kGateNow.toUtc();

  Payment pay(
    String id,
    int athleteIndex,
    int amount,
    String concept,
    PaymentStatus status, {
    int? dueInDays,
    int createdDaysAgo = 10,
    int? paidDaysAgo,
  }) {
    return Payment(
      id: id,
      trainerId: kGateTrainerId,
      athleteId: kGateAthletes[athleteIndex].id,
      amountArs: amount,
      concept: concept,
      status: status,
      createdAt: base.subtract(Duration(days: createdDaysAgo)),
      paidAt: paidDaysAgo == null
          ? null
          : base.subtract(Duration(days: paidDaysAgo)),
      dueAt: dueInDays == null ? null : base.add(Duration(days: dueInDays)),
    );
  }

  return [
    // Vencidos — dueAt en el pasado.
    pay('gate-pay-1', 0, 42000, 'Plan mensual', PaymentStatus.pending,
        dueInDays: -9, createdDaysAgo: 39),
    pay('gate-pay-2', 3, 128500, 'Plan trimestral', PaymentStatus.pending,
        dueInDays: -2, createdDaysAgo: 32),
    // Por vencer — dueAt adelante.
    pay('gate-pay-3', 1, 42000, 'Plan mensual', PaymentStatus.pending,
        dueInDays: 6, createdDaysAgo: 24),
    // Cobrados.
    pay('gate-pay-4', 2, 38000, 'Plan mensual', PaymentStatus.paid,
        createdDaysAgo: 35, paidDaysAgo: 33),
    pay('gate-pay-5', 4, 20000, 'Sesión suelta', PaymentStatus.paid,
        createdDaysAgo: 12, paidDaysAgo: 12),
    pay('gate-pay-6', 5, 42000, 'Plan mensual', PaymentStatus.paid,
        createdDaysAgo: 5, paidDaysAgo: 4),
  ];
}

/// Adherencia agregada que muestra el hero del dashboard.
///
/// 78 %: ni redondo ni al borde de un umbral de color. Un 80 exacto no
/// distinguiría un `>=` de un `>` si alguien lo cambia.
const double kGateAdherencePct = 78;

/// Alumnos sin sesión en 14 días. Dos de seis — suficiente para que la alerta
/// de inactivos se renderice en su forma plural.
List<String> gateInactiveAthleteIds() => [
      kGateAthletes[4].id,
      kGateAthletes[5].id,
    ];

/// Chats sin leer. Alimenta el contador del botón "Mensajes (N)" del hero del
/// dashboard — el sidebar de Chat NO tiene badge (sólo lo tienen Solicitudes y
/// Pagos). A dos dígitos el botón cambia de ancho, y ese es el caso que
/// conviene tener fotografiado.
const int kGateUnreadChats = 12;

/// Hilos de chat del PF con tres de sus alumnos.
///
/// Los `lastMessageAt` caen en tres rangos distintos a propósito, porque
/// `_formatTimestamp` de `chat_list_pane.dart` elige formato según cuán viejo
/// es: hoy → `HH:mm`, esta semana → día abreviado, más viejo → `dd/MM`. Con los
/// tres hilos el golden cubre las tres ramas de una sola captura; con tres
/// mensajes del mismo día cubriría una.
///
/// Dos quedan sin leer (`lastRead` del PF anterior al último mensaje) y uno
/// leído: el indicador de no-leído es un estado visual propio.
List<Chat> gateChats() {
  final base = kGateNow.toUtc();

  Chat thread(
    int athleteIndex, {
    required Duration ago,
    required String text,
    required bool unread,
  }) {
    final athlete = kGateAthletes[athleteIndex];
    final lastAt = base.subtract(ago);
    return Chat(
      chatId: 'gate-chat-${athlete.id}',
      members: [kGateTrainerId, athlete.id],
      createdAt: base.subtract(const Duration(days: 90)),
      lastMessageAt: lastAt,
      lastMessageText: text,
      lastMessageSenderId: athlete.id,
      lastRead: {
        kGateTrainerId:
            unread ? lastAt.subtract(const Duration(days: 1)) : lastAt,
        athlete.id: lastAt,
      },
      linkId: 'gate-link-${athlete.id}',
    );
  }

  return [
    // Hoy, 08:15 → se rinde como `HH:mm`.
    thread(0,
        ago: const Duration(hours: 2, minutes: 15),
        text: '¿Puedo mover la sesión del jueves?',
        unread: true),
    // Sin emoji a propósito: no hay fuente de emoji bundleada, así que un 💪
    // en el seed sale como cajita y se hornea en el golden. Que la app no
    // rinda emoji es un hallazgo real, pero el seed no es el lugar para
    // descubrirlo — sería ruido permanente en dos capturas.
    // Anteayer → día abreviado.
    thread(2,
        ago: const Duration(days: 2),
        text: 'Listo, terminé el bloque de fuerza',
        unread: true),
    // Hace tres semanas → `dd/MM`.
    thread(1,
        ago: const Duration(days: 21),
        text: 'Gracias por el plan nuevo',
        unread: false),
  ];
}

/// Mediciones de un alumno: dos tomas separadas por 30 días.
///
/// Dos y no una: la ficha muestra el delta de peso a 30 días, y con una sola
/// toma ese widget cae a su estado vacío — el golden no fotografiaría el camino
/// que importa. Los valores bajan 1,4 kg para que el delta salga negativo, que
/// es la rama con color propio.
List<Measurement> gateMeasurements(String athleteId) {
  final base = kGateNow.toUtc();
  Measurement at(String id, int daysAgo, double weight, double fat) =>
      Measurement(
        id: id,
        athleteId: athleteId,
        recordedBy: kGateTrainerId,
        recordedAt: base.subtract(Duration(days: daysAgo)),
        weightKg: weight,
        fatPercentage: fat,
      );

  return [
    at('gate-meas-2', 3, 81.2, 17.4),
    at('gate-meas-1', 33, 82.6, 18.1),
  ];
}
