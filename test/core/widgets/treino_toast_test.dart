// #1560 / #1490: helper único de toasts. El caso clave es el del sheet: el
// SnackBar del ScaffoldMessenger vive en el Scaffold de ATRÁS y queda tapado
// por la ruta modal; el helper tiene que ser visible igual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/core/widgets/treino_toast.dart';

Widget _app({required Widget home}) =>
    MaterialApp(theme: AppTheme.dark(), home: home);

class _Boton extends StatelessWidget {
  const _Boton(this.onTap);
  final void Function(BuildContext) onTap;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      );
}

void main() {
  testWidgets('muestra el mensaje en un SnackBar y su ícono por tipo',
      (tester) async {
    await tester.pumpWidget(_app(
      home: _Boton(
          (c) => showTreinoToast(c, 'Guardado', type: TreinoToastType.success)),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Guardado'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, TreinoIcon.check);
    final palette = AppTheme.dark().extension<AppPalette>()!;
    expect(icon.color, palette.accent);
  });

  testWidgets('error e info usan ícono y color propios', (tester) async {
    final palette = AppTheme.dark().extension<AppPalette>()!;
    for (final (tipo, icono, color) in [
      (TreinoToastType.error, TreinoIcon.errorState, palette.dangerText),
      (TreinoToastType.info, TreinoIcon.infoCircle, palette.textMuted),
    ]) {
      await tester.pumpWidget(_app(
        home: _Boton((c) => showTreinoToast(c, 'x', type: tipo)),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, icono);
      expect(icon.color, color);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('con acción, el botón dispara el callback', (tester) async {
    var llamado = false;
    await tester.pumpWidget(_app(
      home: _Boton((c) => showTreinoToast(
            c,
            'Borrado',
            action: TreinoToastAction(
              label: 'DESHACER',
              onPressed: () => llamado = true,
            ),
          )),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('DESHACER'));
    await tester.pump();
    expect(llamado, isTrue);
  });

  testWidgets('desde un bottom sheet el toast queda ENCIMA del sheet (#1490)',
      (tester) async {
    await tester.pumpWidget(_app(
      home: _Boton((c) => showModalBottomSheet<void>(
            context: c,
            builder: (sheetCtx) => SizedBox(
              height: 300,
              width: double.infinity,
              child: Center(
                child: TextButton(
                  onPressed: () => showTreinoToast(sheetCtx, 'Elegí un alumno.',
                      type: TreinoToastType.error),
                  child: const Text('registrar'),
                ),
              ),
            ),
          )),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('registrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Visible: está en el overlay raíz, por encima de la ruta del sheet, y su
    // centro cae dentro de la pantalla (no detrás del sheet).
    final toast = find.text('Elegí un alumno.');
    expect(toast, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getCenter(toast).dy, lessThan(600));
    // hitTest: lo que está en la posición del toast ES el toast (no el sheet).
    final res = tester.hitTestOnBinding(tester.getCenter(toast));
    expect(
      res.path.any((e) => e.target.toString().contains('RenderParagraph')),
      isTrue,
    );

    // Se auto-descarta.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Elegí un alumno.'), findsNothing);
  });
}
