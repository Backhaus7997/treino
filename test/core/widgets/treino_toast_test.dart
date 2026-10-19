// #1560 / #1490: helper único de toasts. El caso clave es el del sheet: el
// SnackBar del ScaffoldMessenger vive en el Scaffold de ATRÁS y queda tapado
// por la ruta modal; el helper tiene que ser visible igual.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
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

/// Abre un bottom sheet con un botón que dispara el toast desde su context.
Widget _appConSheet(String mensaje) => _app(
      home: _Boton((c) => showModalBottomSheet<void>(
            context: c,
            builder: (sheetCtx) => SizedBox(
              height: 300,
              width: double.infinity,
              child: Center(
                child: TextButton(
                  onPressed: () => showTreinoToast(sheetCtx, mensaje),
                  child: const Text('registrar'),
                ),
              ),
            ),
          )),
    );

Future<void> _abrirSheetYDisparar(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('registrar'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// El `Material` visible del SnackBar (sin el margen que lo envuelve).
/// La tarjeta visible del toast (fondo, borde y radio del kit), dentro del
/// SnackBar o del Overlay.
Finder _cuerpoDelSnack() => find.byKey(const Key('treino-toast-card'));

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

  testWidgets(
      'con bottomNavigationBar + extendBody el toast queda PEGADO a la barra '
      '(el Scaffold ya descuenta su alto; un margen extra lo duplica)',
      (tester) async {
    const altoBarra = 92.0;
    const keyBarra = Key('barra');
    await tester.pumpWidget(_app(
      home: Scaffold(
        extendBody: true,
        bottomNavigationBar: const SizedBox(key: keyBarra, height: altoBarra),
        body: Builder(
          builder: (c) => Center(
            child: TextButton(
              onPressed: () => showTreinoToast(c, 'Guardado'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final gap = tester.getTopLeft(find.byKey(keyBarra)).dy -
        tester.getBottomLeft(_cuerpoDelSnack()).dy;
    expect(gap, greaterThanOrEqualTo(0), reason: 'el toast pisa la barra');
    expect(gap, lessThanOrEqualTo(20), reason: 'gap de $gap px sobre la barra');
  });

  testWidgets(
      'el estilo TREINO lo pone el helper en el SnackBar, no el tema global',
      (tester) async {
    await tester.pumpWidget(_app(
      home: _Boton((c) => showTreinoToast(c, 'Guardado')),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final palette = AppTheme.dark().extension<AppPalette>()!;
    // El SnackBar es el portador transparente; la tarjeta visible va
    // adentro (#1593: así el ancho se recalcula en cada layout).
    final sb = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(sb.behavior, SnackBarBehavior.floating);
    expect(sb.backgroundColor, Colors.transparent);
    expect(sb.elevation, 0);
    expect(sb.margin, isNotNull);
    final card = tester.widget<Material>(_cuerpoDelSnack());
    expect(card.color, palette.bgCard);
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.sm));
    expect(shape.side.color, palette.border);
  });

  testWidgets(
      'desde un sheet con el teclado abierto el toast queda ARRIBA '
      'del teclado', (tester) async {
    const teclado = 300.0;
    tester.view.viewInsets = FakeViewPadding(
      bottom: teclado * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(_appConSheet('Elegí un alumno.'));
    await _abrirSheetYDisparar(tester);

    final alto = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.text('Elegí un alumno.')).dy,
      lessThanOrEqualTo(alto - teclado),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el toast por Overlay se anuncia (live region)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_appConSheet('Elegí un alumno.'));
    await _abrirSheetYDisparar(tester);

    SemanticsNode? nodo = tester.getSemantics(find.text('Elegí un alumno.'));
    var esLive = false;
    while (nodo != null && !esLive) {
      esLive = nodo.getSemanticsData().hasFlag(SemanticsFlag.isLiveRegion);
      nodo = nodo.parent;
    }
    expect(esLive, isTrue);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets(
      'si el árbol se va con un toast por Overlay vivo, no queda un Timer '
      'pendiente', (tester) async {
    await tester.pumpWidget(_appConSheet('Elegí un alumno.'));
    await _abrirSheetYDisparar(tester);
    // Sin esperar los 4 s: el framework falla con `!timersPending` si el
    // Timer del toast sobrevive al árbol.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con un context desmontado no explota', (tester) async {
    late BuildContext viejo;
    await tester.pumpWidget(_app(
      home: Builder(builder: (c) {
        viejo = c;
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(_app(home: const Text('otra')));
    expect(() => showTreinoToast(viejo, 'tarde'), returnsNormally);
    await tester.pump();
    expect(find.text('tarde'), findsNothing);
  });

  testWidgets('un SnackBar nuevo cierra el toast por Overlay, y viceversa',
      (tester) async {
    late BuildContext pantalla;
    late BuildContext sheet;
    await tester.pumpWidget(_app(
      home: _Boton((c) {
        pantalla = c;
        showModalBottomSheet<void>(
          context: c,
          builder: (s) {
            sheet = s;
            return const SizedBox(height: 300, width: double.infinity);
          },
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    showTreinoToast(pantalla, 'del messenger');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);

    showTreinoToast(sheet, 'del overlay');
    await tester.pumpAndSettle();
    expect(find.text('del overlay'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'el SnackBar de atrás tiene que irse');

    showTreinoToast(pantalla, 'otra vez messenger');
    await tester.pump();
    expect(find.text('del overlay'), findsNothing,
        reason: 'el toast por Overlay tiene que irse');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'en una página fullscreenDialog con Scaffold propio el SnackBar se ve '
      '(no hace falta el Overlay)', (tester) async {
    await tester.pumpWidget(_app(
      home: _Boton((c) => Navigator.of(c).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _Boton((d) => showTreinoToast(d, 'Visible')),
          ))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final centro = tester.getCenter(find.text('Visible'));
    final res = tester.hitTestOnBinding(centro);
    expect(
      res.path.any((e) => e.target.toString().contains('RenderParagraph')),
      isTrue,
    );
  });

  testWidgets('duration alarga la vida del toast con acción', (tester) async {
    await tester.pumpWidget(_app(
      home: _Boton((c) => showTreinoToast(
            c,
            'Sacado',
            duration: const Duration(seconds: 6),
            action: TreinoToastAction(label: 'Deshacer', onPressed: () {}),
          )),
    ));
    await tester.tap(find.text('go'));
    // El timer del SnackBar arranca cuando termina la animación de entrada.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Sacado'), findsOneWidget,
        reason: 'a los 5 s sigue: el default de 4 no alcanza para decidir');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sacado'), findsNothing,
        reason: 'con acción igual se va solo (persist: false)');
  });

  testWidgets('bottomOffset levanta el toast por encima de un pie fijo',
      (tester) async {
    Future<double> fondoCon(double offset) async {
      await tester.pumpWidget(_app(
        home: _Boton((c) => showTreinoToast(c, 'Hola', bottomOffset: offset)),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final fondo = tester.getBottomLeft(_cuerpoDelSnack()).dy;
      await tester.pumpWidget(const SizedBox());
      return fondo;
    }

    final base = await fondoCon(0);
    final levantado = await fondoCon(88);
    expect(base - levantado, moreOrLessEquals(88));
  });

  group('ancho en pantallas anchas (Coach Hub web)', () {
    Future<Rect> rectDelToast(
      WidgetTester tester,
      Size pantalla, {
      bool enSheet = false,
    }) async {
      tester.view.physicalSize = pantalla;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (enSheet) {
        await tester.pumpWidget(_appConSheet('Guardado'));
        await _abrirSheetYDisparar(tester);
        await tester.pumpAndSettle();
        final rect = tester.getRect(_cuerpoDelSnack());
        await tester.pumpWidget(const SizedBox());
        return rect;
      }
      await tester.pumpWidget(_app(
        home: _Boton((c) => showTreinoToast(c, 'Guardado')),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return tester.getRect(_cuerpoDelSnack());
    }

    testWidgets('en un monitor no pasa de 560 y queda centrado',
        (tester) async {
      final r = await rectDelToast(tester, const Size(1440, 900));
      expect(r.width, moreOrLessEquals(560));
      expect(r.center.dx, moreOrLessEquals(720));
    });

    testWidgets('en el teléfono manda el margen lateral de 20', (tester) async {
      final r = await rectDelToast(tester, const Size(390, 844));
      expect(r.left, moreOrLessEquals(AppSpacing.s20));
      expect(r.width, moreOrLessEquals(390 - 2 * AppSpacing.s20));
    });

    // Codex en #1593: el margen lateral se calculaba una vez, al encolar el
    // SnackBar. Achicando la ventana del navegador con el toast a la vista,
    // los 440 px de cada lado de 1440 quedaban aplicados a 600 y el toast se
    // quedaba sin ancho.
    testWidgets('si la ventana se achica con el toast a la vista, se adapta',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        home: _Boton((c) => showTreinoToast(c, 'Guardado')),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(tester.getSize(_cuerpoDelSnack()).width, moreOrLessEquals(560));

      tester.view.physicalSize = const Size(600, 900);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_cuerpoDelSnack()).width,
          moreOrLessEquals(600 - 2 * AppSpacing.s20));

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pump();
      expect(tester.getSize(_cuerpoDelSnack()).width, moreOrLessEquals(560),
          reason: 'y al agrandarla vuelve al máximo');
    });

    testWidgets('el toast por Overlay respeta el mismo máximo', (tester) async {
      final r =
          await rectDelToast(tester, const Size(1440, 900), enSheet: true);
      expect(r.width, moreOrLessEquals(560));
    });
  });
}
