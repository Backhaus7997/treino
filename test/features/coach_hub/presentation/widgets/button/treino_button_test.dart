import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

Widget _wrap(Widget child, {bool light = false}) => MaterialApp(
      theme: light ? AppTheme.light() : AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

BoxDecoration _decorationOf(WidgetTester tester, Key key) => tester
    .widget<Container>(
      find.descendant(of: find.byKey(key), matching: find.byType(Container)),
    )
    .decoration! as BoxDecoration;

void main() {
  group('TreinoButton — un padding y un alto por tamaño', () {
    // La razón de existir del componente: `alumno_detail_screen.dart` tenía
    // siete paddings distintos y seis tamaños de ícono, y dos botones
    // contiguos con el MISMO padding declarado reportaban cajas de alto
    // distinto. Acá el alto sale del enum y no del llamador.
    testWidgets('sm mide 32 de alto y md mide 40', (tester) async {
      await tester.pumpWidget(_wrap(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TreinoButton(
              key: Key('sm'),
              label: 'Chat',
              size: TreinoButtonSize.sm,
              onPressed: _noop,
            ),
            TreinoButton(key: Key('md'), label: 'Guardar', onPressed: _noop),
          ],
        ),
      ));

      expect(tester.getSize(find.byKey(const Key('sm'))).height, 32);
      expect(tester.getSize(find.byKey(const Key('md'))).height, 40);
    });

    // Material 3 fuerza un tap target de 48x48 vía `_InputPadding` —
    // invisible, pero cuenta para el layout. De los 59 botones del detalle
    // sólo 6 lo acotaban; los otros 53 arrastraban 48 px de aire fantasma.
    testWidgets(
        'el alto REPORTADO es el del tamaño, sin el padding fantasma '
        'de Material 3', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoButton(
          key: Key('b'),
          label: 'Chat',
          size: TreinoButtonSize.sm,
          onPressed: _noop,
        ),
      ));

      final caja = tester.getSize(find.byKey(const Key('b')));
      expect(caja.height, lessThan(48),
          reason: 'si mide 48 volvió el tap target de Material 3');
      expect(caja.height, 32);
    });

    testWidgets('dos botones contiguos de mismo tamaño miden IGUAL',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TreinoButton(
              key: Key('a'),
              label: 'Chat',
              size: TreinoButtonSize.sm,
              variant: TreinoButtonVariant.secondary,
              icon: TreinoIcon.chat,
              onPressed: _noop,
            ),
            TreinoButton(
              key: Key('b'),
              label: 'Pago',
              size: TreinoButtonSize.sm,
              variant: TreinoButtonVariant.secondary,
              onPressed: _noop,
            ),
          ],
        ),
      ));

      expect(
        tester.getSize(find.byKey(const Key('a'))).height,
        tester.getSize(find.byKey(const Key('b'))).height,
        reason: 'es el bug medido en el header del detalle: 16 vs 19 px',
      );
    });
  });

  group('TreinoButton — hover', () {
    // El hover NO anima. Lo fija además el guard estático
    // `no_animated_hover_scan_test.dart`, pero acá se prueba el efecto y no
    // la ausencia de un patrón: un scanner jamás dice que algo FUNCIONA.
    testWidgets('el fondo cambia al pasar el cursor', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoButton(
          key: Key('b'),
          label: 'Guardar',
          onPressed: _noop,
        ),
      ));

      final reposo = _decorationOf(tester, const Key('b')).color;

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('b'))));
      await tester.pump();

      expect(_decorationOf(tester, const Key('b')).color, isNot(reposo));
    });

    testWidgets('el fondo del hover es VISIBLEMENTE distinto, en ambos temas',
        (tester) async {
      // El mismo criterio que el guard de `TreinoListRow`: «distinto» no es la
      // propiedad que importa, «se nota» sí. El hover de la fila pasaba el
      // test de desigualdad con un delta de 5 sobre 255 y era invisible.
      for (final light in [false, true]) {
        await tester.pumpWidget(_wrap(
          const TreinoButton(
            key: Key('b'),
            label: 'Guardar',
            variant: TreinoButtonVariant.secondary,
            onPressed: _noop,
          ),
          light: light,
        ));

        final ctx = tester.element(find.byKey(const Key('b')));
        final visual =
            TreinoButtonTokens.of(ctx, TreinoButtonVariant.secondary);
        final fondo = AppPalette.of(ctx).bgCard;

        final compuesto = Color.alphaBlend(visual.hoverBackground, fondo);
        int ch(double x) => (x * 255).round();
        final delta = [
          (ch(compuesto.r) - ch(fondo.r)).abs(),
          (ch(compuesto.g) - ch(fondo.g)).abs(),
          (ch(compuesto.b) - ch(fondo.b)).abs(),
        ].reduce((a, b) => a > b ? a : b);

        expect(delta, greaterThanOrEqualTo(8),
            reason: '${light ? 'light' : 'dark'}: el hover no se ve '
                '(delta $delta)');
      }
    });
  });

  group('TreinoButton — deshabilitado y accesibilidad', () {
    testWidgets('onPressed null → no llama y no cambia de tamaño',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoButton(key: Key('b'), label: 'Guardar', onPressed: null),
      ));
      final apagado = tester.getSize(find.byKey(const Key('b')));

      await tester.tap(find.byKey(const Key('b')), warnIfMissed: false);
      await tester.pump();

      await tester.pumpWidget(_wrap(
        const TreinoButton(key: Key('b'), label: 'Guardar', onPressed: _noop),
      ));
      expect(tester.getSize(find.byKey(const Key('b'))), apagado,
          reason: 'deshabilitar no puede mover lo que está al lado');
    });

    testWidgets('tap llama a onPressed', (tester) async {
      var toques = 0;
      await tester.pumpWidget(_wrap(
        TreinoButton(
          key: const Key('b'),
          label: 'Guardar',
          onPressed: () => toques++,
        ),
      ));
      await tester.tap(find.byKey(const Key('b')));
      await tester.pump();
      expect(toques, 1);
    });

    testWidgets('TreinoIconButton se nombra UNA sola vez para el lector',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        const TreinoIconButton(
          key: Key('b'),
          icon: TreinoIcon.trash,
          tooltip: 'Eliminar',
          onPressed: _noop,
        ),
      ));

      // Se pide desde el Icon y no desde la key: `getSemantics` sube por el
      // árbol, así que desde el widget de afuera devolvería el nodo del
      // Scaffold.
      final nodo = tester.getSemantics(find.byIcon(TreinoIcon.trash));
      expect(nodo.label, 'Eliminar',
          reason: 'el Tooltip y el Semantics sumaban dos labels: «$nodo»');
      handle.dispose();
    });

    testWidgets('TreinoIconButton es CUADRADO (una fila de estos alinea sola)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoIconButton(
          key: Key('b'),
          icon: TreinoIcon.chat,
          tooltip: 'Chat',
          onPressed: _noop,
        ),
      ));
      final caja = tester.getSize(find.byKey(const Key('b')));
      expect(caja.width, caja.height);
      expect(caja.height, TreinoButtonSize.sm.height);
    });
  });
}

void _noop() {}
