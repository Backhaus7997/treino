// La compactación que mantiene cada superserie como una corrida CONSECUTIVA.
//
// `_blocks()` en el editor y `supersetBlockIndices` en el dominio arman los
// grupos recorriendo corridas de slots consecutivos que comparten el mismo
// `supersetGroup`. Escribir el mismo id NO alcanza: si algo los separa en la
// lista, se ven —y se guardan— como dos bloques distintos.
//
// Los dos casos que lo rompían, encontrados por el bot de review:
//
//   - Unir dos vecinos VISIBLES con un slot oculto en el medio. El oculto
//     —ausente en la semana en curso, ADR-WPRES— los sigue separando en
//     `day.slots`.
//   - Sacar al miembro del MEDIO de un grupo de tres: los de los costados
//     quedan con el mismo id y ya no contiguos.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

void main() {
  List<int?> compactar(List<int?> grupos) =>
      RoutineEditorTestBridge.gruposContiguosBridge(grupos);

  test('una lista ya contigua no se toca', () {
    expect(compactar([null, 1, 1, null]), [null, 1, 1, null]);
  });

  test('un suelto en el medio de un grupo se corre afuera', () {
    // El caso de "sacar al del medio": queda [1, null, 1].
    expect(compactar([1, null, 1]), [1, 1, null],
        reason: 'los dos miembros se juntan y el suelto queda detrás');
  });

  test('dos miembros separados por un slot ajeno se juntan', () {
    // El caso de "unir con un slot oculto en el medio".
    expect(compactar([1, null, 1, null]), [1, 1, null, null]);
  });

  test('el grupo se ancla donde aparece su PRIMER miembro', () {
    expect(compactar([null, 1, null, 1]), [null, 1, 1, null],
        reason: 'el suelto de adelante no se mueve: sólo se trae al grupo');
  });

  test('dos grupos distintos no se mezclan', () {
    expect(compactar([1, 2, 1, 2]), [1, 1, 2, 2]);
  });

  test('el orden relativo de los sueltos se conserva', () {
    final r = compactar([null, null, 1, null, 1]);
    expect(r, [null, null, 1, 1, null]);
  });

  test('una lista sin grupos queda igual', () {
    expect(compactar([null, null, null]), [null, null, null]);
  });

  test('una lista vacía no rompe', () {
    expect(compactar([]), isEmpty);
  });

  test('un grupo de tres partido en dos tramos se junta', () {
    expect(compactar([1, null, 1, null, 1]), [1, 1, 1, null, null]);
  });
}
