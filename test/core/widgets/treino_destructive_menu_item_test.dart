import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_destructive_menu_item.dart';

void main() {
  testWidgets('TreinoDestructiveMenuItem pinta el texto en dangerText',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: PopupMenuButton<int>(
            itemBuilder: (_) => [
              TreinoDestructiveMenuItem<int>(
                  value: 1, child: const Text('ELIMINAR')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text('ELIMINAR'));
    final style = DefaultTextStyle.of(ctx).style;
    expect(style.color, AppPalette.mintMagenta.dangerText);
  });
}
