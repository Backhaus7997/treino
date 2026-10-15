// StaleDataNotice + `isStale` — aviso «Datos desactualizados · Reintentar» del
// Coach Hub (stream que falló DESPUÉS de cargar).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/stale_async.dart';
import 'package:treino/features/coach_hub/presentation/widgets/stale_data_notice.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('isStale', () {
    final error = AsyncError<int>(Exception('x'), StackTrace.empty);

    test('data sola no es stale', () {
      expect(const AsyncData(1).isStale, isFalse);
    });

    test('error sin valor no es stale (es un error de primer load)', () {
      expect(error.isStale, isFalse);
    });

    test('valor previo + error es stale', () {
      expect(error.copyWithPrevious(const AsyncData(1)).isStale, isTrue);
    });

    test('valor previo + error MIENTRAS reintenta no es stale', () {
      final retrying = const AsyncLoading<int>()
          .copyWithPrevious(error.copyWithPrevious(const AsyncData(1)));
      expect(retrying.hasValue && retrying.hasError, isTrue);
      expect(retrying.isStale, isFalse);
    });
  });

  group('StaleDataNotice', () {
    testWidgets('muestra el texto y «Reintentar» llama onRetry',
        (tester) async {
      var taps = 0;
      await _pump(tester, StaleDataNotice(onRetry: () => taps++));

      expect(find.text('Datos desactualizados'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      expect(taps, 1);
    });

    testWidgets('expone una región semántica con el mensaje', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, StaleDataNotice(onRetry: () {}));

      expect(
        find.bySemanticsLabel('Datos desactualizados'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('staleNoticeIf(false) no dibuja nada y deja el hueco',
        (tester) async {
      await _pump(tester, staleNoticeIf(false, () {}));
      expect(find.byType(StaleDataNotice), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);

      await _pump(tester, staleNoticeIf(true, () {}));
      expect(find.byType(StaleDataNotice), findsOneWidget);
    });
  });
}
