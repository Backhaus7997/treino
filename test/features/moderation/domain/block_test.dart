import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/moderation/domain/block.dart';

Block _edge({
  String blocker = 'u1',
  String blocked = 'u2',
}) =>
    Block(
      id: Block.edgeId(blocker, blocked),
      blockerUid: blocker,
      blockedUid: blocked,
      members: [blocker, blocked],
      createdAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  group('Block.edgeId', () {
    test('es {blocker}_{blocked}, NO ordenado', () {
      // Mismo motivo que Follow.edgeId: si se ordenara, las dos direcciones
      // colisionarían en el mismo documento.
      expect(Block.edgeId('u1', 'u2'), 'u1_u2');
      expect(Block.edgeId('u2', 'u1'), 'u2_u1');
    });

    test('las dos direcciones de un par dan ids DISTINTOS', () {
      expect(Block.edgeId('a', 'b'), isNot(Block.edgeId('b', 'a')));
    });
  });

  group('Block — forma del documento', () {
    test('members es [blocker, blocked], en ese orden', () {
      final e = _edge(blocker: 'u1', blocked: 'u2');
      expect(e.members, ['u1', 'u2']);
    });

    test('el id coincide con edgeId(blockerUid, blockedUid)', () {
      final e = _edge(blocker: 'abc', blocked: 'xyz');
      expect(e.id, Block.edgeId(e.blockerUid, e.blockedUid));
    });

    // REGRESIÓN: firestore.rules valida `create` de `blocks` con
    // hasOnly(['blockerUid', 'blockedUid', 'members', 'createdAt']) — CUATRO
    // campos, sin `id` (a diferencia de `follows`, cuya regla SÍ incluye
    // `id` en su hasOnly y lo valida contra el doc id). Si `toJson()`
    // incluyera `id`, BlockRepository.block() escribiría una key de más y
    // Firestore rechazaría el write con PERMISSION_DENIED en TODOS los
    // casos — bloquear a alguien nunca funcionaría.
    test('toJson() NO incluye "id" (firestore.rules: hasOnly sin id)', () {
      final json = _edge().toJson();
      expect(json.containsKey('id'), isFalse);
      expect(
        json.keys.toSet(),
        {'blockerUid', 'blockedUid', 'members', 'createdAt'},
      );
    });

    test(
        'round-trip JSON preserva dirección — id se reinyecta al leer, '
        'igual que Follow._fromDoc', () {
      final original = _edge();
      // Simula lo que hace BlockRepository._fromDoc: el id sale del doc id
      // de Firestore (snap.id), no del body.
      final vuelta = Block.fromJson({...original.toJson(), 'id': original.id});

      expect(vuelta, original);
      expect(vuelta.blockerUid, 'u1');
      expect(vuelta.blockedUid, 'u2');
    });

    test('dos aristas opuestas del mismo par son documentos distintos', () {
      final ida = _edge(blocker: 'a', blocked: 'b');
      final vuelta = _edge(blocker: 'b', blocked: 'a');

      expect(ida.id, isNot(vuelta.id));
      expect(ida, isNot(vuelta));
      expect(ida.members, containsAll(['a', 'b']));
      expect(vuelta.members, containsAll(['a', 'b']));
    });
  });
}
