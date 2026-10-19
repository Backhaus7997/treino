import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_destructive_menu_item.dart';
import 'package:treino/core/widgets/treino_icon.dart';

Future<void> _abrir(
  WidgetTester tester,
  List<PopupMenuEntry<int>> items,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: PopupMenuButton<int>(itemBuilder: (_) => items),
      ),
    ),
  );
  await tester.tap(find.byType(PopupMenuButton<int>));
  await tester.pumpAndSettle();
}

TextStyle _estilo(WidgetTester tester, String texto) =>
    DefaultTextStyle.of(tester.element(find.text(texto))).style;

void main() {
  const danger = AppPalette.mintMagenta;

  testWidgets('TreinoDestructiveMenuItem pinta el texto en dangerText',
      (tester) async {
    await _abrir(tester, [
      TreinoDestructiveMenuItem<int>(value: 1, child: const Text('ELIMINAR')),
    ]);

    expect(_estilo(tester, 'ELIMINAR').color, danger.dangerText);
  });

  testWidgets('deshabilitado NO se pinta de peligro: usa el disabled del tema',
      (tester) async {
    await _abrir(tester, [
      const PopupMenuItem<int>(
        value: 0,
        enabled: false,
        child: Text('NORMAL'),
      ),
      TreinoDestructiveMenuItem<int>(
        value: 1,
        enabled: false,
        child: const Text('ELIMINAR'),
      ),
    ]);

    final estilo = _estilo(tester, 'ELIMINAR');
    expect(estilo.color, isNot(danger.dangerText));
    expect(estilo.color, _estilo(tester, 'NORMAL').color);
  });

  testWidgets('con ícono: ícono y texto en dangerText', (tester) async {
    await _abrir(tester, [
      TreinoDestructiveMenuItem<int>(
        value: 1,
        icon: TreinoIcon.trash,
        child: const Text('Eliminar'),
      ),
    ]);

    expect(_estilo(tester, 'Eliminar').color, danger.dangerText);
    final icon = tester.widget<Icon>(find.byIcon(TreinoIcon.trash));
    expect(icon.color, danger.dangerText);
  });

  testWidgets('con ícono y deshabilitado: el ícono tampoco es de peligro',
      (tester) async {
    await _abrir(tester, [
      TreinoDestructiveMenuItem<int>(
        value: 1,
        enabled: false,
        icon: TreinoIcon.trash,
        child: const Text('Eliminar'),
      ),
    ]);

    final icon = tester.widget<Icon>(find.byIcon(TreinoIcon.trash));
    expect(icon.color, isNot(danger.dangerText));
  });
}
