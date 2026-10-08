import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

Widget _harness({required ThemeData theme, required Widget child}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
  );
}

void main() {
  // `AppTheme.dark()`/`light()` resuelven tipografía por GoogleFonts, y eso
  // toca `ServicesBinding.instance`. Como acá los temas se construyen en el
  // encabezado del `for` —o sea, al RECOLECTAR los tests, antes de que corra
  // ninguno—, sin esta línea el binding todavía no existe y los tres casos
  // mueren con "Binding has not yet been initialized" antes de la primera
  // aserción.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in <(String, ThemeData)>[
    ('oscuro', AppTheme.dark()),
    ('claro', AppTheme.light()),
  ]) {
    testWidgets('TreinoDropdown usa tokens en tema ${entry.$1}',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          theme: entry.$2,
          child: TreinoDropdown<String>(
            initialValue: 'uno',
            items: const [
              DropdownMenuItem(value: 'uno', child: Text('Uno')),
              DropdownMenuItem(value: 'dos', child: Text('Dos')),
            ],
            onChanged: (_) {},
          ),
        ),
      );

      final context = tester.element(find.byType(TreinoDropdown<String>));
      final palette = AppPalette.of(context);
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      final button = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );

      expect(button.dropdownColor, TreinoCardTokens.background(context));
      expect(button.borderRadius, BorderRadius.circular(AppRadius.md));
      expect(button.style?.fontFamily, AppFonts.barlow);
      expect(field.decoration.fillColor, palette.bgCard);
      expect(
        (field.decoration.enabledBorder as OutlineInputBorder).borderRadius,
        BorderRadius.circular(AppRadius.sm),
      );
    });
  }

  testWidgets('TreinoPopupMenuButton tokeniza superficie y esquinas',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.light(),
        child: TreinoPopupMenuButton<String>(
          tooltip: 'Acciones',
          onSelected: (_) {},
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
          ],
          child: const Text('Abrir'),
        ),
      ),
    );

    final context = tester.element(find.byType(TreinoPopupMenuButton<String>));
    final button = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>),
    );
    final shape = button.shape as RoundedRectangleBorder;

    expect(button.color, TreinoCardTokens.background(context));
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.md));
    expect(shape.side.color, TreinoCardTokens.border(context));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
  });
}
