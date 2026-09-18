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
}
