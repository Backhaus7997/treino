// El estado «bloqueado» del roster (paywall Fase 7, downgrade).
//
// Un vínculo bloqueado sigue teniendo `status: active` — `entitlement` es un
// overlay ortogonal (ADR-1). Si el roster mirara sólo `status`, mostraría
// «Activo» sobre un alumno que no cuenta para el límite y con el que el PF no
// va a poder trabajar. Eso es mentirle al PF en la única pantalla donde podría
// entender qué le pasó.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_entitlement.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart';

TrainerLink _link({
  required TrainerLinkStatus status,
  TrainerLinkEntitlement entitlement = TrainerLinkEntitlement.entitled,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: 'l_$athleteId',
      trainerId: 't1',
      athleteId: athleteId,
      status: status,
      entitlement: entitlement,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('estadoForLink — bloqueado', () {
    test('bloqueado MANDA sobre active', () {
      expect(
        estadoForLink(
          _link(
            status: TrainerLinkStatus.active,
            entitlement: TrainerLinkEntitlement.blocked,
          ),
          const {},
        ),
        AlumnoEstado.bloqueado,
      );
    });

    test('bloqueado MANDA sobre con deuda', () {
      // Son dos problemas distintos y el bloqueo es el que el PF puede
      // resolver: la deuda es del alumno, el bloqueo es de su suscripción.
      expect(
        estadoForLink(
          _link(
            status: TrainerLinkStatus.active,
            entitlement: TrainerLinkEntitlement.blocked,
          ),
          {'a1'},
        ),
        AlumnoEstado.bloqueado,
      );
    });

    test('bloqueado MANDA sobre pausado', () {
      expect(
        estadoForLink(
          _link(
            status: TrainerLinkStatus.paused,
            entitlement: TrainerLinkEntitlement.blocked,
          ),
          const {},
        ),
        AlumnoEstado.bloqueado,
      );
    });

    test('entitled no cambia nada de lo anterior', () {
      expect(
        estadoForLink(_link(status: TrainerLinkStatus.active), const {}),
        AlumnoEstado.activo,
      );
      expect(
        estadoForLink(_link(status: TrainerLinkStatus.paused), const {}),
        AlumnoEstado.pausado,
      );
      expect(
        estadoForLink(_link(status: TrainerLinkStatus.active), {'a1'}),
        AlumnoEstado.conDeuda,
      );
    });

    test('sin entitlement en el doc decodifica entitled (sin backfill)', () {
      // Todos los vínculos que existían antes del paywall no tienen el campo.
      // Si defaultearan a blocked, el roster entero aparecería bloqueado.
      final sinCampo = TrainerLink(
        id: 'viejo',
        trainerId: 't1',
        athleteId: 'a1',
        status: TrainerLinkStatus.active,
        requestedAt: DateTime.utc(2026, 1, 1),
      );
      expect(estadoForLink(sinCampo, const {}), AlumnoEstado.activo);
    });
  });
}
