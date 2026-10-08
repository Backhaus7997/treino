import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/pager/coach_hub_pager.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

final _cien = List<int>.generate(100, (i) => i);

void main() {
  group('pageOf — el recorte', () {
    test('la primera página son los primeros 25', () {
      final p = pageOf(_cien, page: 0);
      expect(p.length, 25);
      expect(p.first, 0);
      expect(p.last, 24);
    });

    test('la última página puede venir corta', () {
      // 30 elementos: 25 + 5. El resto no se rellena ni se recorta a 25.
      final p = pageOf(List<int>.generate(30, (i) => i), page: 1);
      expect(p.length, 5);
      expect(p.first, 25);
    });

    test('una lista más corta que la página entra entera', () {
      final p = pageOf([1, 2, 3], page: 0);
      expect(p, [1, 2, 3]);
    });

    test('lista vacía devuelve vacío sin explotar', () {
      expect(pageOf(<int>[], page: 3), isEmpty);
    });

    test('una página fuera de rango CLAMPEA a la última con contenido', () {
      // Este es el caso cotidiano, no el borde raro: el PF marca pagado el
      // último pendiente, el bucket se achica, y la página en la que estaba
      // parado deja de existir. Devolver vacío se leería como "no hay nada"
      // teniendo datos; tirar convertiría un evento normal en un crash.
      final p = pageOf(_cien, page: 99);
      expect(p.first, 75);
      expect(p.length, 25);
    });

    test('una página negativa clampea a la primera', () {
      expect(pageOf(_cien, page: -4).first, 0);
    });
  });

  group('pageCount — cuántas páginas', () {
    test('un múltiplo exacto no inventa una página de más', () {
      // 50 / 25 son DOS páginas, no tres. El `+ pageSize - 1` del techo es
      // justo el error que se comete acá.
      expect(pageCount(50), 2);
    });

    test('el resto suma una página', () => expect(pageCount(51), 3));

    test('una lista vacía sigue siendo "1 de 1", no "1 de 0"', () {
      expect(pageCount(0), 1);
    });
  });

  group('CoachHubPager — el pie', () {
    testWidgets('con una sola página no se dibuja nada', (tester) async {
      // Un paginador de una página es ruido, y además miente sobre el tamaño
      // de la lista. La mayoría de las listas del Coach Hub viven abajo de 25
      // filas durante mucho tiempo.
      await tester.pumpWidget(_wrap(
        CoachHubPager(total: 12, page: 0, onPageChanged: (_) {}),
      ));

      expect(find.byKey(const Key('coach_hub_pager_next')), findsNothing);
      expect(find.textContaining('de 12'), findsNothing);
    });

    testWidgets('el rango dice qué tramo se está viendo', (tester) async {
      await tester.pumpWidget(_wrap(
        CoachHubPager(total: 112, page: 1, onPageChanged: (_) {}),
      ));

      expect(find.text('26–50 de 112'), findsOneWidget);
    });

    testWidgets('la última página muestra el corte real, no el teórico',
        (tester) async {
      // 112 elementos, página 4 (0-based): 101–112, no 101–125.
      await tester.pumpWidget(_wrap(
        CoachHubPager(total: 112, page: 4, onPageChanged: (_) {}),
      ));

      expect(find.text('101–112 de 112'), findsOneWidget);
    });

    testWidgets('en la primera página "anterior" está deshabilitado',
        (tester) async {
      var pedida = -1;
      await tester.pumpWidget(_wrap(
        CoachHubPager(total: 60, page: 0, onPageChanged: (p) => pedida = p),
      ));

      await tester.tap(find.byKey(const Key('coach_hub_pager_prev')));
      await tester.pumpAndSettle();
      expect(pedida, -1, reason: 'no debería haber pedido ninguna página');

      await tester.tap(find.byKey(const Key('coach_hub_pager_next')));
      await tester.pumpAndSettle();
      expect(pedida, 1);
    });

    testWidgets('en la última página "siguiente" está deshabilitado',
        (tester) async {
      var pedida = -1;
      await tester.pumpWidget(_wrap(
        CoachHubPager(total: 60, page: 2, onPageChanged: (p) => pedida = p),
      ));

      await tester.tap(find.byKey(const Key('coach_hub_pager_next')));
      await tester.pumpAndSettle();
      expect(pedida, -1);

      await tester.tap(find.byKey(const Key('coach_hub_pager_prev')));
      await tester.pumpAndSettle();
      expect(pedida, 1);
    });
  });
}
