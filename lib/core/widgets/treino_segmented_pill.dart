import 'dart:math' as math;

import 'package:flutter/material.dart';

// El barrel, no el archivo suelto: es la API pública del design system
// (docs/design-system.md:29). Este widget usa SÓLO los tokens de capa 3 que
// expone `TreinoSegmentedPillTokens` — nunca `AppColorPrimitives`, que el
// barrel también reexporta pero es insumo exclusivo de `AppPalette`.
import '../../app/theme/tokens/tokens.dart';

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
/// La migración va en dos PRs: Entrenar y Coach primero, Feed y el discovery de
/// PFs después. Hasta que aterricen los dos, esas dos pantallas siguen con su
/// `TabBar` inline. La quinta copia —Coach Hub web— es aparte: ver #667.
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
class TreinoSegmentedPill extends StatefulWidget {
  const TreinoSegmentedPill({
    super.key,
    required this.labels,
    this.onTap,
    this.scrollable = false,
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

  /// Fuerza el modo scrolleable, sin esperar a que la escala de texto lo pida.
  ///
  /// El default (`false`) alcanza para dos o tres celdas: ahí repartir el ancho
  /// se ve bien y sólo hace falta scrollear con dynamic type grande, que es lo
  /// que ya decide la heurística de abajo.
  ///
  /// Con MUCHAS celdas eso no aplica: la ficha de alumno del Coach Hub tiene
  /// **once** pestañas, y repartir el ancho entre once las deja ilegibles a
  /// escala de texto 1.0 — antes de que la heurística se active. Este flag
  /// existe para ese caso.
  ///
  /// Es un OR, no un override: con `scrollable: true` el control scrollea
  /// siempre, y con `false` la heurística de escala de texto sigue mandando.
  /// Nunca puede APAGAR el scroll que el dynamic type necesita, que sería
  /// cambiar una decisión de accesibilidad por una de layout.
  final bool scrollable;

  @override
  State<TreinoSegmentedPill> createState() => _TreinoSegmentedPillState();
}

class _TreinoSegmentedPillState extends State<TreinoSegmentedPill> {
  /// `const` a mano: `BorderRadius.circular` no es const-construible, y esto
  /// se reconstruye en cada build de las pantallas migradas.
  static const _trackRadius = BorderRadius.all(
    Radius.circular(TreinoSegmentedPillTokens.trackRadius),
  );

  /// Mismo valor que [_trackRadius] hoy —los dos son `AppRadius.full`— pero se
  /// leen de tokens distintos a propósito: si algún día la pista y el thumb
  /// dejan de ser concéntricos, el cambio es de un token y no de este archivo.
  static const _segmentRadius = BorderRadius.all(
    Radius.circular(TreinoSegmentedPillTokens.segmentRadius),
  );

  /// Si alguna celda tiene el foco de teclado.
  ///
  /// El único estado del widget, y existe por una razón concreta: el overlay
  /// de foco de `TabBar` NO se ve sobre la celda activa, porque la tinta de
  /// Material se pinta debajo del subárbol y el thumb opaco la tapa. Sin esto,
  /// un usuario de teclado que activa una pestaña pierde el indicador de foco
  /// justo donde queda parado — WCAG 2.4.7.
  ///
  /// El anillo va en la PISTA, no en la celda: ahí el z-order deja de
  /// importar, y no hace falta abandonar el `indicator` de `TabBar` ni saber
  /// cuál de las celdas tiene el foco.
  bool _hasFocus = false;

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
      scaledLabelHeight + TreinoSegmentedPillTokens.labelVerticalRoom,
    );

    // Por encima del umbral, repartir el ancho deja las etiquetas ilegibles;
    // scrollear nunca desborda, así que es el fallback seguro. El call site
    // puede pedirlo de entrada cuando ya sabe que tiene demasiadas celdas.
    final isScrollable = widget.scrollable ||
        textScaler.scale(1) >
            TreinoSegmentedPillTokens.scrollTextScaleThreshold;

    return Focus(
      // No participa de la navegación: sólo observa. `hasFocus` de un nodo
      // `Focus` es true si él o CUALQUIER descendiente tiene el foco primario,
      // que es exactamente lo que hace falta para saber si el teclado está
      // parado en alguna celda sin tocar los `FocusNode` que crea `TabBar`.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        if (value != _hasFocus) setState(() => _hasFocus = value);
      },
      child: Container(
        padding: const EdgeInsets.all(TreinoSegmentedPillTokens.trackPadding),
        decoration: BoxDecoration(
          color: t.trackFill,
          borderRadius: _trackRadius,
          // Anillo por fuera con `spreadRadius`, no un borde más grueso: un
          // borde desplazaría el contenido 2pt al enfocar y la fila entera
          // saltaría.
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: TreinoFocusTokens.of(context).ring,
                    spreadRadius: TreinoFocusTokens.ringWidth,
                  ),
                ]
              : null,
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
          // 0 y no el default de 2: `TabBar` mete un `Padding` de
          // `indicatorWeight` abajo de CADA tab siempre, incluso cuando el
          // `indicator` es propio y no la barrita de Material. Con el default la
          // celda medía 46pt contra los 44 de `Tab.height` y el label quedaba
          // 1px arriba del centro del thumb.
          indicatorWeight: 0,
          indicator: BoxDecoration(
            color: t.activeFill,
            borderRadius: _segmentRadius,
            // El keyline es lo único que identifica el estado seleccionado en
            // tema claro: el mint sobre una pista clara da 1.64:1. En dark es
            // invisible e inocuo — ahí el 3:1 lo carga el relleno.
            border: Border.all(
              color: TreinoSegmentedPillTokens.activeInk,
              width: TreinoSegmentedPillTokens.borderWidth,
            ),
          ),
          splashBorderRadius: _segmentRadius,
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
          onTap: widget.onTap,
          tabs: [
            for (final label in widget.labels)
              Tab(
                height: segmentHeight,
                // `FittedBox` subsume las tres estrategias de overflow que
                // convivían: encoge antes que desbordar.
                //
                // Ojo con las tres propiedades del `Text`: adentro de un
                // `FittedBox` son INERTES. `RenderFittedBox` layoutea al hijo con
                // `BoxConstraints()` vacío, o sea ancho infinito, así que nunca
                // hay wrap que `softWrap: false` pueda evitar, nunca hay segunda
                // línea que `maxLines` recorte y nunca hay overflow que `fade`
                // atenúe. Quien evita el desborde es el `scaleDown`.
                //
                // Se conservan igual porque `workout_screen_test.dart` las
                // asertea desde antes de esta migración, y porque describen la
                // intención si alguien saca el `FittedBox`. No agregues tests
                // sobre ellas: pasarían por construcción sin verificar nada.
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
      ),
    );
  }
}
