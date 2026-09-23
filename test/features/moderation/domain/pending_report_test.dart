import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/moderation/domain/pending_report.dart';

PendingReport _reporte({DateTime? creado, DateTime? visto}) =>
    PendingReport.fromMap({
      'id': 'post_p1_r1',
      'targetKind': 'post',
      'targetId': 'p1',
      'targetOwnerUid': 'o1',
      'reason': 'harassment',
      'reporterUid': 'r1',
      'detail': 'me dijeron cosas',
      'createdAt': creado?.toIso8601String(),
      'firstViewedAt': visto?.toIso8601String(),
      'contentPath': 'posts/p1',
    });

void main() {
  final ahora = DateTime.now().toUtc();

  group('rompioElPlazo', () {
    test('mirado en tiempo y todavia abierto NO rompe nada', () {
      // Lo que se promete es REVISAR dentro de las 24 horas, no resolver. Un
      // reporte atendido a las dos horas que sigue abierto —porque resolverlo
      // requiere decidir algo— no incumple la promesa publicada.
      //
      // El criterio tiene que ser IDENTICO al de `moderationStats` del
      // servidor: si la pantalla pinta de rojo lo que el servidor cuenta como
      // en regla, el moderador deja de creerle a los dos.
      final r = _reporte(
        creado: ahora.subtract(const Duration(hours: 100)),
        visto: ahora.subtract(const Duration(hours: 99)),
      );
      expect(r.rompioElPlazo, isFalse);
    });

    test('mirado TARDE sigue rompiendo, aunque ya se haya mirado', () {
      // Mirarlo despues no deshace el incumplimiento.
      final r = _reporte(
        creado: ahora.subtract(const Duration(hours: 100)),
        visto: ahora.subtract(const Duration(hours: 10)),
      );
      expect(r.rompioElPlazo, isTrue);
    });

    test('nunca mirado y todavia en plazo tampoco rompe', () {
      final r = _reporte(creado: ahora.subtract(const Duration(hours: 2)));
      expect(r.rompioElPlazo, isFalse);
    });

    test('nunca mirado y vencido, si', () {
      final r = _reporte(creado: ahora.subtract(const Duration(hours: 30)));
      expect(r.rompioElPlazo, isTrue);
    });

    test('sin fecha no inventa un incumplimiento', () {
      expect(_reporte().rompioElPlazo, isFalse);
      expect(_reporte().horasDesdeQueEntro, isNull);
    });
  });

  group('fromMap', () {
    test('un campo que el servidor deja de mandar no lo rompe', () {
      // Una cola que no abre porque el servidor cambio una clave deja al
      // equipo sin la herramienta justo cuando corre el reloj.
      final r = PendingReport.fromMap(const {'id': 'x'});
      expect(r.id, 'x');
      expect(r.reason, isEmpty);
      expect(r.contentPath, isNull);
      expect(r.detail, isNull);
    });

    test('lee la ruta del contenido que resuelve el servidor', () {
      expect(_reporte().contentPath, 'posts/p1');
    });
  });

  group('uidDeclaradoNoCoincide', () {
    PendingReport con(String? derivado) => PendingReport.fromMap({
          'id': 'post_p1_r1',
          'targetOwnerUid': 'o1',
          if (derivado != null) 'derivedOwnerUid': derivado,
        });

    test('el declarado y el derivado iguales NO es mismatch', () {
      // Una alarma que grita siempre entrena a ignorarla, y el caso normal
      // es este.
      expect(con('o1').uidDeclaradoNoCoincide, isFalse);
    });

    test('distintos SI es mismatch', () {
      // Señal de reporte malicioso: se denuncia contenido de uno escribiendo
      // el uid de otro.
      expect(con('otro').uidDeclaradoNoCoincide, isTrue);
    });

    test('sin derivado no se afirma un mismatch que no se puede saber', () {
      // `null` significa "no se pudo derivar el autor", no "es otro". Tratar
      // la ignorancia como acusación es la misma clase de afirmación sin
      // verificar que AGENTS.md 11.1 trata.
      expect(con(null).uidDeclaradoNoCoincide, isFalse);
    });
  });

  group('campos nuevos de la cola', () {
    test('lee el autor derivado, su nombre y el intento previo', () {
      final r = PendingReport.fromMap(const {
        'id': 'x',
        'derivedOwnerUid': 'uid-real',
        'derivedOwnerName': 'Juan',
        'attemptedAction': 'userSuspended',
        'attemptedAt': '2026-09-23T10:00:00.000Z',
      });
      expect(r.derivedOwnerUid, 'uid-real');
      expect(r.derivedOwnerName, 'Juan');
      expect(r.attemptedAction, 'userSuspended');
      expect(r.attemptedAt, DateTime.utc(2026, 9, 23, 10));
    });

    test('sin esos campos quedan en null, no en vacio', () {
      // La diferencia importa: "" se renderizaria como un autor sin nombre.
      final r = PendingReport.fromMap(const {'id': 'x'});
      expect(r.derivedOwnerUid, isNull);
      expect(r.derivedOwnerName, isNull);
      expect(r.attemptedAction, isNull);
      expect(r.attemptedAt, isNull);
    });
  });
}
