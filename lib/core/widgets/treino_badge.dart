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
/// La lectura obvia de la cápsula es "declara mínimos y no declara techos", y
/// lleva a poner un `maxHeight: 16`. La causa real es otra: **un [Container]
/// con `alignment` se expande a llenar las constraints acotadas que reciba** —
/// comportamiento documentado del widget, no un bug. En un `Row` el eje
/// horizontal viene sin acotar y por eso a lo ancho no se vio nunca; en el
/// vertical, con la fila ajustada a 48, se comió los 48 enteros. Y el
/// `alignment` no se puede sacar: es lo que centra el dígito cuando el
/// `minWidth` agranda la caja más que el texto.
///
/// Las cinco configuraciones, medidas —no razonadas— corriendo el test de este
/// widget contra cada una:
///
/// | envoltorio + constraints | alto bajo padre ajustado a 48 | ancho con constraints sueltas de 800 |
/// | --- | --- | --- |
/// | ninguno (las dos copias viejas) | **48** ✗ | **800** ✗ |
/// | `maxHeight: 16`, sin envoltorio | **48** ✗ — `enforce` lo sube | **800** ✗ |
/// | `Align(widthFactor: 1, heightFactor: 1)` | **48** ✗ | **800** ✗ |
/// | `Align` + `maxHeight: 16` | 16 ✓ | **800** ✗ |
/// | [UnconstrainedBox] | 16 ✓ | 16 ✓ |
///
/// Dos cosas que la tabla deja claras y el razonamiento a mano no:
///
/// 1. **El `maxHeight` solo no alcanza, pero no por lo que parece.** Sin
///    envoltorio lo clampea `BoxConstraints.enforce`, que sube las constraints
///    propias al rango del padre: `16` bajo un padre ajustado en `48` da `48`.
///    Debajo de un `Align` —que ya aflojó a `0..48`— el mismo `maxHeight` sí
///    funciona. O sea que el techo depende de quién esté arriba, que es
///    exactamente la clase de arreglo que se rompe cuando alguien mueve el
///    widget de lugar.
/// 2. **El ancho no admite techo, y ahí se cae toda la familia de soluciones
///    con `max*`.** Un badge de tres dígitos TIENE que crecer, así que no hay
///    `maxWidth` que poner. La fila `Align + maxHeight` es la trampa: arregla
///    el eje que el gate visual mostró y deja vivo el otro.
///
/// Por eso el envoltorio es [UnconstrainedBox]: es el único que le pasa al hijo
/// constraints **sin acotar**, y contra un infinito el "expandirse a llenar" no
/// tiene nada que llenar. El badge se mide entonces por su contenido y sus
/// mínimos —16×16 con un dígito— y si el padre igual le impone una caja más
/// grande, el `UnconstrainedBox` la ocupa y centra adentro un badge que sigue
/// redondo.
///
/// Todo esto lo fija `test/core/widgets/treino_badge_test.dart`: los números de
/// la tabla salen de correrlo contra cada configuración.
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
