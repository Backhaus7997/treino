import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/invite_outcome.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

TrainerLink _link(String trainerId, TrainerLinkStatus status) => TrainerLink(
      id: 'l1',
      trainerId: trainerId,
      athleteId: 'atleta',
      status: status,
      requestedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('sin PF (caso C)', () {
    test('la invitación se puede aplicar directo', () {
      final r = resolveInvite(
        inviteTrainerId: 'pf-nuevo',
        athleteId: 'atleta',
        vinculoActual: null,
      );

      expect(r, isA<InvitePuedeVincular>());
      expect((r as InvitePuedeVincular).trainerId, 'pf-nuevo');
    });
  });

  group('mismo PF (caso D)', () {
    test('vínculo activo: no se duplica nada', () {
      final r = resolveInvite(
        inviteTrainerId: 'pf-1',
        athleteId: 'atleta',
        vinculoActual: _link('pf-1', TrainerLinkStatus.active),
      );

      // El corazón del caso D. Si esto devolviera `puedeVincular`, abrir dos
      // veces el mismo link dejaría dos vínculos con el mismo PF.
      expect(r, isA<InviteYaVinculado>());
    });

    test('solicitud pendiente: no es lo mismo que estar vinculado', () {
      final r = resolveInvite(
        inviteTrainerId: 'pf-1',
        athleteId: 'atleta',
        vinculoActual: _link('pf-1', TrainerLinkStatus.pending),
      );

      // Decirle "ya estás vinculado" a alguien que está esperando que el PF
      // acepte es mentirle sobre el estado de su propia cuenta.
      expect(r, isA<InviteYaSolicitado>());
    });
  });

  group('otro PF (caso E)', () {
    test('pide desvincular y expone el vínculo a terminar', () {
      final actual = _link('pf-viejo', TrainerLinkStatus.active);
      final r = resolveInvite(
        inviteTrainerId: 'pf-nuevo',
        athleteId: 'atleta',
        vinculoActual: actual,
      );

      // Nunca se resuelve solo: cambiar de entrenador es decisión del alumno,
      // y el link le pudo llegar reenviado o lo pudo tocar sin querer.
      expect(r, isA<InviteRequiereDesvincular>());
      final e = r as InviteRequiereDesvincular;
      expect(e.nuevoTrainerId, 'pf-nuevo');
      expect(e.vinculoActual.id, actual.id,
          reason: 'la UI necesita el id para poder terminarlo');
    });

    test('también con una solicitud pendiente a otro PF', () {
      final r = resolveInvite(
        inviteTrainerId: 'pf-nuevo',
        athleteId: 'atleta',
        vinculoActual: _link('pf-viejo', TrainerLinkStatus.pending),
      );

      // Un pending a otro PF ocupa el único cupo igual que un activo: el
      // repositorio deshabilita "pedir vínculo" con cualquiera de los dos.
      expect(r, isA<InviteRequiereDesvincular>());
    });
  });

  group('no aplica', () {
    test('el PF abriendo su propio link', () {
      // Pasa de verdad: el PF prueba que el link anda. Ofrecerle vincularse
      // consigo mismo sería absurdo, y el repositorio lo rechaza igual.
      final r = resolveInvite(
        inviteTrainerId: 'pf-1',
        athleteId: 'pf-1',
        vinculoActual: null,
      );

      expect(r, isA<InviteNoAplica>());
    });

    test('invitación sin PF', () {
      expect(
        resolveInvite(
            inviteTrainerId: '', athleteId: 'atleta', vinculoActual: null),
        isA<InviteNoAplica>(),
      );
    });
  });

  test('abrir el MISMO link dos veces no cambia el resultado', () {
    // Idempotencia, que es lo que pide el flujo: doble click, refresh, o el
    // link abierto dos veces desde el chat.
    final actual = _link('pf-1', TrainerLinkStatus.active);
    InviteOutcome resolver() => resolveInvite(
          inviteTrainerId: 'pf-1',
          athleteId: 'atleta',
          vinculoActual: actual,
        );

    expect(resolver().runtimeType, resolver().runtimeType);
    expect(resolver(), isA<InviteYaVinculado>());
  });
}
