import 'package:flutter/material.dart';

import '../../app/theme/tokens/tokens.dart';

/// Badge numérico del kit TREINO — el contador de no-leídos que va sobre un
/// ítem del sidebar del Coach Hub o al lado de un chip de filtro.
///
/// ## Por qué existe
///
/// `TreinoBadgeTokens` documenta "16px, círculo, pill completa" desde que se
/// creó, pero era sólo un puñado de constantes: cada pantalla armaba su propio
/// `Container` y ninguna de las dos copias que había cumplía el contrato.
///
/// | copia | cómo medía | qué rompía |
/// | --- | --- | --- |
/// | sidebar del Coach Hub | `minWidth`/`minHeight: 16`, sin techo | un padre con altura ajustada lo estiraba: el gate visual lo capturó como una **cápsula de 20×48** con el dígito flotando al medio |
/// | chips de Biblioteca | `width`/`height: 16` fijos, sin padding | no se deformaba nunca, pero un contador de 3 dígitos no entraba |
///
/// Las dos fallas son la misma discusión sin resolver: **el 16 del token, ¿es
/// un mínimo o una medida?** Acá se resuelve una vez y para todos los call
/// sites: es un **mínimo en las dos dimensiones, con la forma protegida del
/// padre**. Con un dígito el mínimo gana en ambos ejes y sale círculo; con
/// dos o tres el ancho crece y el radio `full` lo convierte en pill; el alto
/// no se mueve nunca.
///
/// ## Quién estiraba el badge: el `alignment`, no el `minHeight`
///
/// La lectura obvia de la cápsula es "declara mínimos y no declara techos". Es
/// la lectura equivocada, y las dos soluciones que salen de ella fallan:
///
/// - **Agregar `maxHeight: 16` no arregla nada.** `BoxConstraints.enforce`
///   clampea las constraints propias **dentro** del rango del padre: bajo un
///   padre con alto ajustado en 48, ese techo de 16 se sube a 48 solo.
/// - **Aflojar con un [Align] tampoco alcanza**, y ese fue el segundo intento.
///   `Align` pasa `constraints.loosen()`, que sigue siendo un rango **acotado**
///   (`0..48`).
///
/// La causa real es que **un [Container] con `alignment` se expande a llenar
/// las constraints acotadas que reciba** — comportamiento documentado del
/// widget, no un bug. En un `Row` el eje horizontal viene sin acotar y por eso
/// nadie lo vio nunca a lo ancho; en el vertical, con la fila ajustada a 48, se
/// comió los 48 enteros. Y el `alignment` no se puede sacar: es lo que centra
/// el dígito cuando el `minWidth` agranda la caja más que el texto.
///
/// Por eso el envoltorio es [UnconstrainedBox] y no `Align`: es el único que le
/// pasa al hijo constraints **sin acotar**, y contra un infinito el "expandirse
/// a llenar" no tiene nada que llenar. El badge se mide entonces por su
/// contenido y sus mínimos —16×16 con un dígito— y si el padre igual le impone
/// una caja más grande, el `UnconstrainedBox` la ocupa y centra adentro un
/// badge que sigue redondo.
///
/// Lo fija `test/core/widgets/treino_badge_test.dart`, que lo mete bajo un
/// padre con altura ajustada de 48px y verifica que siga midiendo 16. Ese test
/// falla —en 800×600, no en 48— contra cualquiera de los dos intentos de
/// arriba.
class TreinoBadge extends StatelessWidget {
  const TreinoBadge({super.key, required this.count});

  /// Cantidad a mostrar. Por encima de [maxCount] se muestra `'99+'`.
  ///
  /// El widget no decide si el badge corresponde: cada call site ya tiene su
  /// propia guarda (`if (hasBadge)`, `if (badgeCount != null)`) porque la
  /// separación con lo que está al lado —el `SizedBox` o el `Padding`— es del
  /// layout que lo contiene, no del badge.
  final int count;

  /// Techo del contador. Arriba de esto el badge dice `'99+'` en vez de
  /// crecer sin límite: tres caracteres es lo último que sigue leyéndose a
  /// `AppTextSize.micro`, y un `1234` estiraría la pill por encima del ítem.
  ///
  /// Salió del tab bar del atleta (`TreinoBottomBar`), que era la única de las
  /// tres copias que había pensado el desborde.
  static const int maxCount = 99;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoBadgeTokens.of(context);
    return UnconstrainedBox(
      child: Container(
        constraints: const BoxConstraints(
          minWidth: TreinoBadgeTokens.size,
          minHeight: TreinoBadgeTokens.size,
        ),
        // Gutter interno de un componente del kit — el caso para el que existe
        // `hairline` (ver su dartdoc). Sin él los dos dígitos se pegan al
        // borde de la pill.
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hairline),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: BorderRadius.circular(TreinoBadgeTokens.borderRadius),
        ),
        child: Text(
          count > maxCount ? '$maxCount+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: AppFonts.w700,
            fontSize: AppTextSize.micro,
            color: tokens.foreground,
          ),
        ),
      ),
    );
  }
}
