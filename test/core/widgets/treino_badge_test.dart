import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/treino_badge_tokens.dart';
import 'package:treino/core/widgets/treino_badge.dart';

/// Monta el badge suelto, sin ningún padre que le imponga tamaño: el caso base
/// contra el que se comparan los demás.
Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

/// El caso que rompía: un padre que estira a sus hijos en el eje vertical.
/// Es la forma que tomó en el sidebar del Coach Hub —una fila de 48px de alto
/// con `crossAxisAlignment: stretch`— y la que el gate visual capturó como una
/// cápsula de 20×48.
Widget _wrapStretched(Widget child, {double height = 48}) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
            ),
          ),
        ),
      ),
    );

Size _badgeBox(WidgetTester tester) => tester.getSize(
      find.descendant(
        of: find.byType(TreinoBadge),
        matching: find.byType(Container),
      ),
    );

void main() {
  group('TreinoBadge — la forma no se negocia con el padre', () {
    testWidgets('suelto, un dígito respeta el mínimo del token en los dos ejes',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoBadge(count: 3)));

      final box = _badgeBox(tester);
      expect(box.height, TreinoBadgeTokens.size);
      // El ancho se compara con `>=` y no con `==` a propósito: en el harness
      // de tests la familia Barlow no resuelve y el dígito se mide con la
      // fuente de fallback, que es bastante más ancha. Que con Barlow real
      // salga círculo exacto lo cubre el gate visual, no este test —
      // asegurarlo acá sería medir la fuente equivocada.
      expect(box.width, greaterThanOrEqualTo(TreinoBadgeTokens.size));
    });

    testWidgets(
        'bajo un padre que estira 48px, el alto sigue siendo el del token',
        (tester) async {
      await tester.pumpWidget(_wrapStretched(const TreinoBadge(count: 3)));

      // LA REGRESIÓN. Antes de `TreinoBadge` acá salía 48, y la causa no era
      // el `minHeight` sin techo: un `Container` con `alignment` se expande a
      // llenar cualquier constraint ACOTADA que reciba. Por eso ni un
      // `maxHeight: 16` (que `enforce` clampea al rango del padre) ni un
      // `Align` (que afloja a `0..48`, que sigue siendo acotado) lo arreglan.
      // Sólo el `UnconstrainedBox` le da al hijo un rango sin acotar, y contra
      // el infinito no hay nada que llenar.
      expect(_badgeBox(tester).height, TreinoBadgeTokens.size);
    });

    testWidgets('el padre que estira mueve el envoltorio, no el badge',
        (tester) async {
      await tester.pumpWidget(_wrapStretched(const TreinoBadge(count: 3)));

      // El `UnconstrainedBox` sí obedece al padre —ocupa los 48— y adentro
      // centra un badge que sigue midiendo 16. Sin esta afirmación el test de
      // arriba pasaría también si el badge se hubiera salido de la fila.
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(TreinoBadge),
                matching: find.byType(UnconstrainedBox),
              ),
            )
            .height,
        48,
      );
    });
  });

  group('TreinoBadge — el contenido hace crecer el ancho, nunca el alto', () {
    testWidgets('tres dígitos ensanchan la pill y dejan el alto quieto',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoBadge(count: 1)));
      final unDigito = _badgeBox(tester);

      await tester.pumpWidget(_wrap(const TreinoBadge(count: 99)));
      final dosDigitos = _badgeBox(tester);

      // La otra copia que había —los chips de Biblioteca— fijaba `width` y
      // `height` en 16: nunca se deformaba, pero un contador de dos o tres
      // dígitos no le entraba. El ancho TIENE que crecer.
      expect(dosDigitos.width, greaterThan(unDigito.width));
      expect(dosDigitos.height, unDigito.height);
      expect(dosDigitos.height, TreinoBadgeTokens.size);
    });

    testWidgets('por encima del techo dice 99+ en vez de estirarse sin fin',
        (tester) async {
      await tester.pumpWidget(_wrap(const TreinoBadge(count: 1234)));

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('1234'), findsNothing);
    });

    testWidgets('justo en el techo todavía muestra el número', (tester) async {
      await tester.pumpWidget(
        _wrap(const TreinoBadge(count: TreinoBadge.maxCount)),
      );

      expect(find.text('99'), findsOneWidget);
    });
  });

  group('TreinoBadge — colores del token en los dos temas', () {
    for (final entry in {
      'dark': AppTheme.dark(),
      'light': AppTheme.light(),
    }.entries) {
      testWidgets('${entry.key}: fondo y texto salen de TreinoBadgeTokens',
          (tester) async {
        await tester.pumpWidget(
          _wrap(const TreinoBadge(count: 7), theme: entry.value),
        );

        final context = tester.element(find.byType(TreinoBadge));
        final tokens = TreinoBadgeTokens.of(context);

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(TreinoBadge),
            matching: find.byType(Container),
          ),
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          tokens.background,
        );
        expect(
          tester.widget<Text>(find.text('7')).style!.color,
          tokens.foreground,
        );
      });
    }
  });
}
