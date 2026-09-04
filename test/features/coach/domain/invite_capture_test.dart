import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/invite_capture.dart';
import 'package:treino/features/coach/domain/trainer_invite_link.dart';

void main() {
  test('reconoce el link que genera el Coach Hub', () {
    // La punta que faltaba del contrato: lo que arma el PF, leído por lo que
    // corre en el teléfono del alumno.
    final link = buildTrainerInviteLink('pf-7')!;

    expect(trainerIdDeInvitacion(Uri.parse(link)), 'pf-7');
  });

  test('los otros deep links no son invitaciones', () {
    // `/abrir/profe?to=agenda` y compañía pasan por el MISMO redirect de nivel
    // superior. Si esto devolviera algo para ellos, cualquier mail de agenda
    // sembraría una invitación fantasma.
    for (final q in ['to=agenda', 'to=solicitudes', 'to=facturacion']) {
      expect(
        trainerIdDeInvitacion(Uri.parse('https://app.gettreino.com/abrir/profe?$q')),
        isNull,
        reason: q,
      );
    }
  });

  test('to=alumno con id NO es una invitación', () {
    // Es el deep link del PF a la ficha de un alumno. Confundirlos vincularía
    // al alumno con... el propio alumno.
    expect(
      trainerIdDeInvitacion(
        Uri.parse('https://app.gettreino.com/abrir/profe?to=alumno&id=a1'),
      ),
      isNull,
    );
  });

  test('una invitación sin pf no es nada', () {
    expect(
      trainerIdDeInvitacion(
        Uri.parse('https://app.gettreino.com/abrir/alumno?to=invitacion'),
      ),
      isNull,
    );
  });

  test('una URL sin query tampoco', () {
    expect(trainerIdDeInvitacion(Uri.parse('https://app.gettreino.com/')), isNull);
    expect(trainerIdDeInvitacion(Uri.parse('/home')), isNull);
  });
}
