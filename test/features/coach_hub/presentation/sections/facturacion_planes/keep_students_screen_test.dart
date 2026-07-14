import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/keep_students_screen.dart';

const _students = [
  KeepableStudent(athleteId: 'a1', displayName: 'Lucas'),
  KeepableStudent(athleteId: 'a2', displayName: 'Sofía'),
  KeepableStudent(athleteId: 'a3', displayName: 'Martín'),
  KeepableStudent(athleteId: 'a4', displayName: 'Ana'),
];

Widget _harness({
  Set<String> initial = const {},
  void Function(Set<String>)? onConfirm,
}) =>
    MaterialApp(
      home: Scaffold(
        body: KeepStudentsScreen(
          students: _students,
          initialSelection: initial,
          onConfirm: onConfirm,
        ),
      ),
    );

void main() {
  testWidgets('muestra todos los alumnos + contador 0/2 sin selección',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Lucas'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('0 / 2 elegidos'), findsOneWidget);
  });

  testWidgets('selección inicial (default) se refleja en el contador',
      (tester) async {
    await tester.pumpWidget(_harness(initial: {'a1', 'a2'}));
    await tester.pump();

    expect(find.text('2 / 2 elegidos'), findsOneWidget);
  });

  testWidgets('no deja elegir más de 2', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(find.text('Lucas'));
    await tester.pump();
    await tester.tap(find.text('Sofía'));
    await tester.pump();
    expect(find.text('2 / 2 elegidos'), findsOneWidget);

    // El 3ro está deshabilitado — el tap no lo agrega.
    await tester.tap(find.text('Martín'));
    await tester.pump();
    expect(find.text('2 / 2 elegidos'), findsOneWidget);
  });

  testWidgets('deseleccionar libera un cupo', (tester) async {
    await tester.pumpWidget(_harness(initial: {'a1', 'a2'}));
    await tester.pump();

    await tester.tap(find.text('Lucas')); // deselecciona a1
    await tester.pump();
    expect(find.text('1 / 2 elegidos'), findsOneWidget);

    // Ahora sí puede elegir otro.
    await tester.tap(find.text('Martín'));
    await tester.pump();
    expect(find.text('2 / 2 elegidos'), findsOneWidget);
  });

  testWidgets('CONFIRMAR solo dispara onConfirm con 2 elegidos',
      (tester) async {
    Set<String>? confirmed;
    await tester.pumpWidget(_harness(
      initial: {'a1'},
      onConfirm: (kept) => confirmed = kept,
    ));
    await tester.pump();

    // Con 1 elegido, el botón está deshabilitado → no dispara. (El botón está
    // más abajo del viewport; scrolleamos para alcanzarlo.)
    await tester.ensureVisible(find.text('CONFIRMAR SELECCIÓN'));
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR SELECCIÓN'), warnIfMissed: false);
    await tester.pump();
    expect(confirmed, isNull);

    // Elijo el 2do → habilitado.
    await tester.tap(find.text('Sofía'));
    await tester.pump();
    await tester.ensureVisible(find.text('CONFIRMAR SELECCIÓN'));
    await tester.pump();
    await tester.tap(find.text('CONFIRMAR SELECCIÓN'));
    await tester.pump();
    expect(confirmed, {'a1', 'a2'});
  });
}
