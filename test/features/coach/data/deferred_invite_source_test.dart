import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/deferred_invite_source.dart';

void main() {
  group('trainerIdDeParamsDeBranch — entrada NO confiable', () {
    test('saca el PF cuando viene bien', () {
      expect(
        trainerIdDeParamsDeBranch({'pf': 'pf-1', '+clicked_branch_link': true}),
        'pf-1',
      );
    });

    test('sin la clave, null', () {
      // Instalación orgánica: alguien bajó la app de la tienda sin ningún
      // link. Branch responde igual, con params que no traen `pf`.
      expect(trainerIdDeParamsDeBranch({'+clicked_branch_link': false}), isNull);
    });

    test('tipos que no son String se descartan', () {
      // Los params son `Map<dynamic, dynamic>` y vienen de la red. Un número
      // o un mapa anidado ahí no es un uid, es basura o un intento.
      expect(trainerIdDeParamsDeBranch({'pf': 42}), isNull);
      expect(trainerIdDeParamsDeBranch({'pf': ['pf-1']}), isNull);
      expect(trainerIdDeParamsDeBranch({'pf': null}), isNull);
    });

    test('vacío o sólo espacios, null', () {
      expect(trainerIdDeParamsDeBranch({'pf': ''}), isNull);
      expect(trainerIdDeParamsDeBranch({'pf': '   '}), isNull);
    });

    test('la clave es la MISMA que la del link propio', () {
      // Las dos vías de entrada —universal link y deferred— tienen que leerse
      // igual. Si divergen, una anda y la otra falla en silencio.
      expect(trainerIdDeParamsDeBranch({'pf': 'pf-1'}), 'pf-1');
    });
  });

  test('sin proveedor configurado no rompe: devuelve null', () async {
    // Es el default de la app y el de los tests. Que falte la clave de un
    // tercero no puede impedir que la app arranque.
    expect(await const SinDeferredInvites().trainerIdDeLaInstalacion(), isNull);
  });
}
