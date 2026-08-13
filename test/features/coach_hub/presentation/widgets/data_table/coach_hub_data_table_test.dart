import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/data_table/coach_hub_data_table.dart';
import 'package:treino/features/coach_hub/presentation/widgets/empty_state/empty_state.dart';

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
      // El indicador de orden activo usa el ícono semántico TreinoIcon
      // (no Icons.arrow_upward crudo) — Finding C4.
      expect(find.byIcon(TreinoIcon.sortAscending), findsOneWidget);
      // La columna 'Sesiones' es sortable pero no está ordenada: debe
      // mostrar el ícono semántico de "ordenable" (caret doble).
      expect(find.byIcon(TreinoIcon.sortable), findsOneWidget);
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
      // El slot vacío debe embeber el componente compartido TreinoEmptyState
      // (no una implementación privada) — Finding C3.
      expect(find.byType(TreinoEmptyState), findsOneWidget);
      expect(find.text('Sin alumnos'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Estado vacío: passthrough de icon/description/CTA a TreinoEmptyState
    // -------------------------------------------------------------------------
    testWidgets(
        'rows vacíos con icon/description/CTA → passthrough a '
        'TreinoEmptyState [SCENARIO-CK-DT-13]', (tester) async {
      var ctaTapped = false;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [],
          emptyMessage: 'Sin alumnos',
          emptyIcon: TreinoIcon.users,
          emptyDescription: 'Invitá a tu primer alumno.',
          emptyCtaLabel: 'Invitar',
          onEmptyCtaTap: () => ctaTapped = true,
        ),
      ));
      await tester.pump();

      final emptyState = tester.widget<TreinoEmptyState>(
        find.byType(TreinoEmptyState),
      );
      expect(emptyState.icon, TreinoIcon.users);
      expect(emptyState.title, 'Sin alumnos');
      expect(emptyState.description, 'Invitá a tu primer alumno.');
      expect(emptyState.ctaLabel, 'Invitar');

      await tester.tap(find.text('Invitar'));
      await tester.pump();
      expect(ctaTapped, isTrue);
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
      // El ícono del estado error usa el ícono semántico TreinoIcon
      // (no Icons.error_outline crudo) — Finding C4.
      expect(find.byIcon(TreinoIcon.errorState), findsOneWidget);
      // Spacing en escala 8/12/14/18/20 — Finding W4 (no padding 32 crudo).
      final errorPadding = tester.widget<Padding>(
        find.byKey(const Key('data_table_error_content')),
      );
      expect(errorPadding.padding, const EdgeInsets.all(AppSpacing.s20));
      await tester.tap(find.byKey(const Key('data_table_retry')));
      await tester.pump();
      expect(retryCalled, isTrue);
    });

    // -------------------------------------------------------------------------
    // Hover fila: decoration usa background de hover (token real)
    // -------------------------------------------------------------------------
    testWidgets(
        'hover fila con onRowTap → decoration usa background de hover '
        '[SCENARIO-CK-DT-08]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          onRowTap: (_) {},
        ),
      ));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('data_table_row_1')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Ana García')));
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)),
          reason: 'el color de fondo debe cambiar realmente en hover');
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
    // onRowTap: fila focusable, Enter activa, expone Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'onRowTap → fila focusable, Enter activa, Semantics(button) '
        '[SCENARIO-CK-DT-11]', (tester) async {
      final handle = tester.ensureSemantics();
      String? tappedId;
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
          onRowTap: (id) => tappedId = id,
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('data_table_row_1')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'fila con onRowTap debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('data_table_row_1'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tappedId, '1', reason: 'Enter debe activar onRowTap');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // Sin onRowTap: fila no focusable, sin Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'sin onRowTap → fila no expone Semantics(button) '
        '[SCENARIO-CK-DT-12]', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('data_table_row_1')),
      );
      expect(semantics.flagsCollection.isButton, isFalse,
          reason: 'fila sin onRowTap no debe ser interactiva');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // cellWidgets: celda-widget reemplaza el string de esa columna
    // -------------------------------------------------------------------------
    testWidgets(
        'cellWidgets con la key de la columna → renderiza el widget dado '
        '[SCENARIO-CK-DT-14]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [
            CoachHubRow(
              id: '1',
              cells: {
                'name': 'Ana García',
                'status': 'Activo',
                'sessions': '12',
              },
              cellWidgets: {
                'status': Chip(
                  key: Key('status_chip_1'),
                  label: Text('Activo'),
                ),
              },
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('status_chip_1')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // cellWidgets: sin celdas-widget la fila sigue mostrando el string (back-compat)
    // -------------------------------------------------------------------------
    testWidgets(
        'sin cellWidgets → columna sigue mostrando el string de cells '
        '[SCENARIO-CK-DT-15]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: _rows,
        ),
      ));
      await tester.pump();

      expect(find.text('Activo'), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
    });

    // -------------------------------------------------------------------------
    // cellWidgets: mezcla string+widget en la misma fila
    // -------------------------------------------------------------------------
    testWidgets(
        'cellWidgets parcial → mezcla widget en una columna y string en '
        'las demás de la misma fila [SCENARIO-CK-DT-16]', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubDataTable(
          columns: _columns,
          rows: const [
            CoachHubRow(
              id: '1',
              cells: {
                'name': 'Ana García',
                'status': 'Activo',
                'sessions': '12',
              },
              cellWidgets: {
                'status': Chip(
                  key: Key('status_chip_1'),
                  label: Text('Activo'),
                ),
              },
            ),
          ],
        ),
      ));
      await tester.pump();

      // Columna 'status' rinde el widget.
      expect(find.byKey(const Key('status_chip_1')), findsOneWidget);
      // Columnas 'name' y 'sessions' siguen renderizando el string de cells.
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
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
