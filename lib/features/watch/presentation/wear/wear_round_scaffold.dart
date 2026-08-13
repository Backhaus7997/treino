import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import 'wear_rotary.dart';

/// Márgenes verticales de Wear OS, en porcentaje del ALTO de pantalla.
///
/// **No son inventados**: son las constantes de `ScalingLazyColumnDefaults` de
/// Horologist. Y no son simétricos ni fijos — dependen del TIPO del primer y del
/// último ítem de la lista, porque un título no necesita el mismo aire que una
/// tarjeta.
///
/// En el SM-L500 (206 dp de diámetro) esto da, por ejemplo, 45 dp arriba y 75 dp
/// abajo para una lista de tarjetas.
///
/// El margen inferior grande NO es espacio muerto: es `padding` de un scroll,
/// así que el último ítem puede subir hasta el centro. Sólo se ve vacío si la
/// lista no scrollea.
enum WearItemType {
  card(0.2188, 0.3646),
  text(0.1664, 0.3646),
  multiButton(0.2188, 0.2083),
  singleButton(0.1248, 0.2083),
  icon(0.1248, 0.2188);

  const WearItemType(this.topPct, this.bottomPct);

  final double topPct;
  final double bottomPct;
}

/// Andamio de pantalla para Wear OS, consciente de que la pantalla es REDONDA.
///
/// ## El error que este archivo vino a corregir
///
/// La primera versión metía TODO el contenido dentro del cuadrado inscripto: un
/// inset uniforme del 16% por lado. En el Samsung SM-L500 —438 px a densidad
/// 340, o sea **206 dp de diámetro**— eso dejaba 140 dp útiles. El dueño lo
/// describió exacto: *"ocupamos un rectángulo al medio con bordes que quedan sin
/// uso"*. El cuadrado inscripto desperdicia el **36% del área** del círculo: es
/// la solución obvia y es la equivocada.
///
/// ## Lo que hacen las apps nativas
///
/// * **Lateral chico**: 5.2% del ancho por lado. Es el número de Horologist.
/// * **Vertical grande y asimétrico**: entre 12% y 36% del alto, según el tipo
///   del primer y último ítem. Va como `padding` de la LISTA, no del andamio:
///   padding vertical en el contenedor recorta el viewport en vez de correr el
///   scroll, y el primer ítem nace cortado contra el bisel sin forma de traerlo
///   a la franja ancha.
/// * **Desvanecido en los bordes**: el recorte del vidrio tiene que leerse como
///   fundido, no como error. Es lo que hace `ScalingLazyColumn` con escalado y
///   opacidad progresivos; acá se aproxima con un [ShaderMask], que da el 80%
///   del efecto con el 5% del código.
class WearRoundScaffold extends StatefulWidget {
  /// Contenido centrado que NO scrollea. Para pantallas de estado: emparejando,
  /// cargando, error.
  const WearRoundScaffold.centered({super.key, required this.children})
      : _scrolls = false,
        firstItem = WearItemType.text,
        lastItem = WearItemType.text;

  /// Lista vertical con la corona conectada.
  ///
  /// [firstItem] y [lastItem] determinan los márgenes de arriba y abajo — ver
  /// [WearItemType].
  const WearRoundScaffold.list({
    super.key,
    required this.children,
    this.firstItem = WearItemType.text,
    this.lastItem = WearItemType.card,
  }) : _scrolls = true;

  /// Margen lateral: 5.2% del ancho por lado, el número de Horologist.
  ///
  /// Es CHICO a propósito. El ancho se gana en la franja central, que es donde
  /// vive lo que el atleta lee: a la altura del centro el círculo mide el 100%
  /// del diámetro.
  static const double horizontalInset = 0.052;

  /// Qué fracción del alto ocupa el desvanecido de cada borde.
  static const double _fade = 0.14;

  final List<Widget> children;
  final WearItemType firstItem;
  final WearItemType lastItem;
  final bool _scrolls;

  @override
  State<WearRoundScaffold> createState() => _WearRoundScaffoldState();
}

class _WearRoundScaffoldState extends State<WearRoundScaffold> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    // El lado corto manda: en un reloj redondo ancho y alto coinciden, pero en
    // uno cuadrado o rectangular no.
    final hPad = size.shortestSide * WearRoundScaffold.horizontalInset;

    if (!widget._scrolls) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
        ),
      );
    }

    final list = ListView(
      controller: _controller,
      padding: EdgeInsets.only(
        top: size.height * widget.firstItem.topPct,
        bottom: size.height * widget.lastItem.bottomPct,
      ),
      children: widget.children,
    );

    return Scaffold(
      backgroundColor: palette.bg,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        // La corona va acá y no en cada pantalla: así hay UN solo scrollable
        // por pantalla y no queda ambiguo a cuál le habla el hardware.
        child: WearRotaryScroll(
          controller: _controller,
          // Sin esto, el primer y el último ítem parecen CORTADOS contra el
          // bisel y el atleta cree que la pantalla se rompió. Con el fundido se
          // lee como "hay más, seguí scrolleando".
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x00000000),
                Color(0xFF000000),
                Color(0xFF000000),
                Color(0x00000000),
              ],
              stops: [
                0,
                WearRoundScaffold._fade,
                1 - WearRoundScaffold._fade,
                1,
              ],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: list,
          ),
        ),
      ),
    );
  }
}
