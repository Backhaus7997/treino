import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens/components/treino_segmented_pill_tokens.dart';

/// Control segmentado de sub-navegación — la pista con dos o más celdas que
/// vive arriba de Entrenar, Feed, Coach y el discovery de PFs.
///
/// Existe por #646: cinco participantes de las pruebas de usabilidad no
/// detectaron estos pills sin ayuda, y varios no entendieron que fueran
/// tocables. La causa no era el contraste del texto —el label inactivo siempre
/// cumplió AA— sino que el control **no tenía contorno visible**: 1.50:1 en
/// dark, 1.26:1 en light, contra los 3:1 que WCAG 1.4.11 pide para identificar
/// un componente. Se leía como un badge de acento al lado de una palabra gris.
/// La aritmética completa vive en [TreinoSegmentedPillTokens].
///
/// Reemplaza cuatro copias del mismo `TabBar` decorado que habían divergido en
/// radio (24 vs 9999), alto (38 vs 40 vs calculado), tipografía (tres fuentes
/// distintas) y estrategia de overflow (tres). **Por eso casi nada es
/// parametrizable**: exponer esos ejes es exactamente cómo se separaron.
///
/// Notas de integración, todas aprendidas de las copias que reemplaza:
///
///  - **No es dueño del `TabController`.** Lee el [DefaultTabController]
///    ambiente, igual que hacían las cuatro. Eso es lo que mantiene funcionando
///    a `_ModeTabScope` en el discovery de PFs, que se cuelga del controller
///    para escribir sus providers, y a los deep links que resuelven
///    `initialIndex` a nivel de pantalla.
///  - **No tiene margen propio.** El call site envuelve en `Padding`.
///  - **`TabBar` no permite decorar la pestaña INACTIVA.** El `indicator` se
///    pinta detrás del hijo del tab, así que un contenedor por pestaña se vería
///    encima del acento en la activa. La afordancia la cargan el contorno de la
///    pista y los overlays de presión, no un relleno por celda.
///  - **No usa `AppMotion`.** La animación del indicador la gobierna
///    `TabController.animationDuration`, que vive en el controller de la
///    pantalla. No lo "arregles" acá: haría falta poseer el controller.
///  - **No modela `disabled`.** `TabBar` no tiene estado deshabilitado por
///    pestaña y ningún call site lo necesita.
class TreinoSegmentedPill extends StatelessWidget {
  const TreinoSegmentedPill({
    super.key,
    required this.labels,
    this.onTap,
  });

  /// Las etiquetas, en orden. La cantidad tiene que coincidir con el `length`
  /// del [DefaultTabController] ancestro.
  ///
  /// Sin `assert` a propósito: `List.length` no es accesible en una expresión
  /// constante, así que agregarlo rompería el ctor `const` y con él los cuatro
  /// call sites. `TabBar` ya valida el desajuste, con un error de framework
  /// menos claro — el trade se paga en claridad de error, no en seguridad.
  final List<String> labels;

  /// Efecto lateral al TOCAR una celda.
  ///
  /// Distinto de escuchar el controller: esto dispara sólo en tap, no en
  /// cambios programáticos de índice ni al swipear el `TabBarView`. La vista de
  /// Coach lo usa para cerrar el sheet del día abierto.
  final ValueChanged<int>? onTap;

  /// `const` a mano: `BorderRadius.circular` no es const-construible, y esto
  /// se reconstruye en cada build de cuatro pantallas.
  static const _radius = BorderRadius.all(
    Radius.circular(TreinoSegmentedPillTokens.segmentRadius),
  );

  @override
  Widget build(BuildContext context) {
    final t = TreinoSegmentedPillTokens.of(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: TreinoSegmentedPillTokens.labelWeight,
          letterSpacing: TreinoSegmentedPillTokens.labelTracking,
        );

    final textScaler = MediaQuery.textScalerOf(context);
    // El alto sigue a la escala de texto en vez de ser fijo: con dynamic type
    // grande un alto fijo recorta el label. El piso es el área tapeable
    // mínima — las cuatro copias originales estaban por debajo.
    final scaledLabelHeight = textScaler.scale(labelStyle?.fontSize ?? 14) *
        (labelStyle?.height ?? 1.2);
    final segmentHeight = math.max(
      TreinoSegmentedPillTokens.minSegmentHeight,
      scaledLabelHeight + TreinoSegmentedPillTokens.segmentVerticalPadding,
    );

    // Por encima del umbral, repartir el ancho deja las etiquetas ilegibles;
    // scrollear nunca desborda, así que es el fallback seguro.
    final isScrollable = textScaler.scale(1) >
        TreinoSegmentedPillTokens.scrollTextScaleThreshold;

    return Container(
      padding: const EdgeInsets.all(TreinoSegmentedPillTokens.trackPadding),
      decoration: BoxDecoration(
        color: t.trackFill,
        // Pista y thumb comparten radio: concéntricos por construcción.
        borderRadius: _radius,
        border: Border.all(
          color: t.trackBorder,
          width: TreinoSegmentedPillTokens.borderWidth,
        ),
      ),
      child: TabBar(
        isScrollable: isScrollable,
        tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
        dividerColor: TreinoSegmentedPillTokens.dividerColor,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: t.activeFill,
          borderRadius: _radius,
          // El keyline es lo único que identifica el estado seleccionado en
          // tema claro: el mint sobre una pista clara da 1.64:1. En dark es
          // invisible e inocuo — ahí el 3:1 lo carga el relleno.
          border: Border.all(
            color: TreinoSegmentedPillTokens.activeInk,
            width: TreinoSegmentedPillTokens.borderWidth,
          ),
        ),
        splashBorderRadius: _radius,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return t.pressedOverlay;
          if (states.contains(WidgetState.hovered)) return t.hoverOverlay;
          if (states.contains(WidgetState.focused)) return t.focusOverlay;
          return null;
        }),
        labelColor: TreinoSegmentedPillTokens.activeInk,
        unselectedLabelColor: t.inactiveLabel,
        labelStyle: labelStyle,
        // El MISMO estilo para los dos estados, a propósito: `TabBar`
        // interpola entre ambos en cada cambio de selección. Con estilos que
        // difieren en familia el salto se ve a mitad de la animación, y si
        // difieren en peso la tira entera se re-layoutea al cambiar de celda.
        // Las dos cosas pasaban en las copias que esto reemplaza.
        unselectedLabelStyle: labelStyle,
        labelPadding: const EdgeInsets.symmetric(
          horizontal: TreinoSegmentedPillTokens.labelPadding,
        ),
        onTap: onTap,
        tabs: [
          for (final label in labels)
            Tab(
              height: segmentHeight,
              // FittedBox + maxLines/softWrap subsume las tres estrategias de
              // overflow que convivían: encoge antes que desbordar, y nunca
              // parte la etiqueta en dos renglones.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
