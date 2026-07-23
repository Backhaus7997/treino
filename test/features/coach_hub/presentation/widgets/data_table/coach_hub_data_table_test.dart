import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/data_table/coach_hub_data_table.dart';

/// Envuelve en MaterialApp con tema dado.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

/// Columnas de prueba.
final _columns = [
  const CoachHubColumn(key: 'name', label: 'Nombre', sortable: true),
  const CoachHubColumn(key: 'status', label: 'Estado', sortable: false),
  const CoachHubColumn(key: 'sessions', label: 'Sesiones', sortable: true),
];

/// Filas de prueba.
final _rows = [
  const CoachHubRow(
    id: '1',
    cells: {'name': 'Ana García', 'status': 'Activo', 'sessions': '12'},
  ),
  const CoachHubRow(
    id: '2',
    cells: {'name': 'Carlos López', 'status': 'Inactivo', 'sessions': '3'},
  ),
];

void main() {
  group('CoachHubDataTable —', () {
    // -------------------------------------------------------------------------
    // Estado normal: encabezados y filas
    // -------------------------------------------------------------------------
    testWidgets('normal → muestra encabezados y datos [SCENARIO-CK-DT-01]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
        ),
      ));
      await tester.pump();
      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Estado'), findsOneWidget);
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('Carlos López'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Columna sortable: muestra indicador de ordenamiento
    // -------------------------------------------------------------------------
    testWidgets(
        'columna sortable → ícono de sort visible '
        '[SCENARIO-CK-DT-02]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          sortColumnKey: 'name',
          sortAscending: true,
        ),
      ));
      await tester.pump();
      // El indicador de sort debe estar presente en la columna 'Nombre'
      expect(find.byKey(const Key('sort_indicator_name')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Tap en columna sortable → llama onSort
    // -------------------------------------------------------------------------
    testWidgets(
        'tap columna sortable → onSort llamado '
        '[SCENARIO-CK-DT-03]', (tester) async {
      String? sortedKey;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          onSort: (key, asc) => sortedKey = key,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Nombre'));
      await tester.pump();
      expect(sortedKey, 'name');
    });

    // -------------------------------------------------------------------------
    // Columna no sortable: tap no llama onSort
    // -------------------------------------------------------------------------
    testWidgets(
        'columna no sortable → tap no llama onSort '
        '[SCENARIO-CK-DT-04]', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          onSort: (_, __) => called = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Estado'));
      await tester.pump();
      expect(called, isFalse);
    });

    // -------------------------------------------------------------------------
    // Estado loading: skeleton shimmer
    // -------------------------------------------------------------------------
    testWidgets(
        'loading=true → skeleton visible, datos ocultos '
        '[SCENARIO-CK-DT-05]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [],
          loading: true,
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('data_table_skeleton')), findsOneWidget);
      expect(find.text('Ana García'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Estado vacío: muestra EmptyState slot
    // -------------------------------------------------------------------------
    testWidgets('rows vacíos → EmptyState visible [SCENARIO-CK-DT-06]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [],
          emptyMessage: 'Sin alumnos',
        ),
      ));
      await tester.pump();
      expect(find.text('Sin alumnos'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Estado error: muestra mensaje de error + botón retry
    // -------------------------------------------------------------------------
    testWidgets(
        'error → mensaje de error y retry visible '
        '[SCENARIO-CK-DT-07]', (tester) async {
      var retryCalled = false;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [],
          errorMessage: 'Error al cargar',
          onRetry: () => retryCalled = true,
        ),
      ));
      await tester.pump();
      expect(find.text('Error al cargar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('data_table_retry')));
      await tester.pump();
      expect(retryCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // Hover fila: no crashea
    // -------------------------------------------------------------------------
    testWidgets('hover fila → no crashea [SCENARIO-CK-DT-08]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
        ),
      ));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Ana García')));
      await tester.pump();
      expect(find.text('Ana García'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // onRowTap: toca fila → callback llamado
    // -------------------------------------------------------------------------
    testWidgets('onRowTap → llamado con row id [SCENARIO-CK-DT-09]',
        (tester) async {
      String? tappedId;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          onRowTap: (id) => tappedId = id,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Ana García'));
      await tester.pump();
      expect(tappedId, '1');
    });

    // -------------------------------------------------------------------------
    // Smoke dark+light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-DT-10]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          CoachHubDataTable(
            columns: _columns,
            rows: _rows,
          ),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('Nombre'), findsOneWidget);
        expect(find.text('Ana García'), findsOneWidget);
      }
    });
  });
}
