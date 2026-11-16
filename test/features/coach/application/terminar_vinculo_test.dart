// #1792 — terminar un vínculo desde el lado del PF cancela los turnos futuros
// del par ANTES de terminar el vínculo.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/terminar_vinculo.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockLinks extends Mock implements TrainerLinkRepository {}

class _MockAppointments extends Mock implements AppointmentRepository {}

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';

final _link = TrainerLink(
  id: 'l1',
  trainerId: _trainerId,
  athleteId: _athleteId,
  status: TrainerLinkStatus.active,
  requestedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late FakeFirebaseFirestore db;
  late AppointmentRepository appointments;
  late _MockLinks links;

  // Lejos en el futuro / en el pasado: no dependen del reloj del test.
  final futuro = DateTime.utc(2099, 1, 1, 10);
  final pasado = DateTime.utc(2020, 1, 1, 10);

  Future<void> seed(String id, DateTime at, {String athlete = _athleteId}) =>
      db.collection('appointments').doc(id).set(Appointment(
            id: id,
            trainerId: _trainerId,
            athleteId: athlete,
            athleteDisplayName: 'Ana',
            startsAt: at,
            durationMin: 60,
            status: AppointmentStatus.confirmed,
          ).toJson());

  Future<String> statusOf(String id) async =>
      (await db.collection('appointments').doc(id).get()).data()!['status']
          as String;

  setUpAll(() => registerFallbackValue(''));

  setUp(() {
    db = FakeFirebaseFirestore();
    appointments = AppointmentRepository(firestore: db);
    links = _MockLinks();
    when(() => links.terminate(any(), reason: any(named: 'reason')))
        .thenAnswer((_) async {});
  });

  group('terminarVinculoLiberandoTurnos', () {
    test('cancela los turnos futuros del par y termina el vínculo', () async {
      await seed('f1', futuro);
      await seed('f2', futuro.add(const Duration(days: 1)));
      await seed('p1', pasado);
      await seed('otro', futuro, athlete: 'otro-athlete');

      final n = await terminarVinculoLiberandoTurnos(
        links: links,
        appointments: appointments,
        link: _link,
      );

      expect(n, 2);
      expect(await statusOf('f1'), 'cancelled');
      expect(await statusOf('f2'), 'cancelled');
      expect(await statusOf('p1'), 'confirmed', reason: 'el pasado no se toca');
      expect(await statusOf('otro'), 'confirmed', reason: 'es de otro alumno');
      verify(() => links.terminate('l1', reason: 'trainer-terminated'))
          .called(1);
      final d = (await db.collection('appointments').doc('f1').get()).data()!;
      expect(((d['cancellationLog']! as List).single as Map)['reason'],
          kMotivoTurnoPorFinDeVinculo);
    });

    test('los turnos ya están cancelados CUANDO se termina el vínculo',
        () async {
      await seed('f1', futuro);
      String? estadoAlTerminar;
      when(() => links.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async => estadoAlTerminar = await statusOf('f1'));

      await terminarVinculoLiberandoTurnos(
        links: links,
        appointments: appointments,
        link: _link,
      );

      expect(estadoAlTerminar, 'cancelled');
    });

    test('si la cancelación falla NO termina el vínculo', () async {
      final roto = _MockAppointments();
      when(() => roto.cancelFutureForPair(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
            actorUid: any(named: 'actorUid'),
            reason: any(named: 'reason'),
          )).thenThrow(Exception('sin red'));

      await expectLater(
        terminarVinculoLiberandoTurnos(
          links: links,
          appointments: roto,
          link: _link,
        ),
        throwsA(isA<TurnosFuturosSinCancelar>()),
      );

      verifyNever(() => links.terminate(any(), reason: any(named: 'reason')));
    });
  });

  group('contarTurnosFuturos', () {
    test('si no se puede contar: null, NO 0 (no sé != ninguno)', () async {
      final roto = _MockAppointments();
      when(() => roto.listFutureConfirmedForPair(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          )).thenThrow(Exception('sin red'));

      expect(await contarTurnosFuturos(roto, _link), isNull);
    });
  });

  group('avisoDeTurnosAlTerminar', () {
    final l10n = lookupAppL10n(const Locale('es', 'AR'));

    test('0 → nada que avisar; 1 → singular; N → plural, con la cuenta', () {
      expect(avisoDeTurnosAlTerminar(l10n, 0), isEmpty);
      expect(avisoDeTurnosAlTerminar(l10n, 1), contains('se cancela 1 sesión'));
      expect(
          avisoDeTurnosAlTerminar(l10n, 3), contains('se cancelan 3 sesiones'));
    });

    test('null → avisa que no pudo revisar, y que igual se cancelan', () {
      final aviso = avisoDeTurnosAlTerminar(l10n, null);
      expect(aviso, contains('No pudimos revisar'));
      expect(aviso, contains('también se cancelan'));
    });
  });
}
