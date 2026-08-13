import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';

/// Andamio de pantalla para Wear OS, consciente de que la pantalla es REDONDA.
///
/// ## Por qué existe
///
/// El spike de medición usaba un `ListView` rectangular y **perdía texto en las
/// esquinas**: en un reloj redondo los cuatro vértices del rectángulo caen
/// fuera del vidrio. No es un detalle estético — el atleta pierde el dato
/// justo cuando levanta la muñeca a mitad de serie.
///
/// ## La geometría, y por qué hay dos modos
///
/// En un círculo de diámetro `D`, el mayor cuadrado inscripto tiene lado
/// `D / √2`, o sea que para que un rectángulo entre COMPLETO hay que meterlo
/// `D · (1 − 1/√2) / 2 ≈ 0.146 · D` desde cada borde. Eso es casi el 30% del
/// ancho perdido, y en una pantalla de reloj eso duele.
///
/// Por eso hay dos modos:
///
/// * [WearRoundScaffold.inscribed] — inset completo. Para contenido que ocupa
///   TODO el alto (listas, filas que llegan a los bordes). Nada se recorta.
/// * [WearRoundScaffold.centered] — inset chico. Para contenido centrado
///   verticalmente, que es donde el círculo es más ancho y hay lugar de sobra.
///   Es el modo del número hero del descanso.
///
/// Elegir mal no rompe la app: recorta texto. Que es peor, porque no se ve en
/// el emulador cuadrado y aparece recién en la muñeca.
class WearRoundScaffold extends StatelessWidget {
  /// Contenido centrado verticalmente. Inset chico: cerca del centro el
  /// círculo es tan ancho como la pantalla.
  const WearRoundScaffold.centered({
    super.key,
    required this.child,
  }) : _inset = _centeredInset;

  /// Contenido que ocupa todo el alto. Inset del cuadrado inscripto, para que
  /// las esquinas no caigan fuera del vidrio.
  const WearRoundScaffold.inscribed({
    super.key,
    required this.child,
  }) : _inset = _inscribedInset;

  /// `(1 − 1/√2) / 2 ≈ 0.146` es el cuadrado inscripto EXACTO — sus cuatro
  /// esquinas TOCAN el círculo. Texto pegado a una esquina queda justo en el
  /// borde del vidrio y se ve cortado: pasó con el título "PLANTILLAS", que se
  /// leía "?LANTILLAS".
  ///
  /// Se agrega un margen para despegarlo del bisel.
  static const double _inscribedInset = 0.16;

  /// Suficiente para despegarse del bisel sin comerse la pantalla.
  static const double _centeredInset = 0.08;

  final Widget child;
  final double _inset;

  /// **No expone `onTap`, y es a propósito.**
  ///
  /// La primera versión ponía un `GestureDetector` con `HitTestBehavior.opaque`
  /// sobre TODA la pantalla. En el reloj físico eso se disparó solo: el log
  /// mostró `startRest → cancelRest → startRest` con un segundo entre medio,
  /// porque cualquier roce del vidrio cuenta como tap.
  ///
  /// En un reloj eso no es un bug menor: el atleta apoya la muñeca en la barra
  /// y se cancela el descanso sin enterarse. Las acciones tienen que ser
  /// objetivos explícitos y acotados, como en el companion de watchOS.
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // El lado corto manda: en un reloj redondo ancho y alto coinciden, pero en
    // uno cuadrado o rectangular no, y el inset tiene que salir del menor.
    final size = MediaQuery.sizeOf(context).shortestSide;
    final pad = size * _inset;

    return Scaffold(
      backgroundColor: palette.bg,
      body: Padding(
        padding: EdgeInsets.all(pad),
        // `centered` centra; `inscribed` LLENA.
        //
        // Centrar contenido más alto que la pantalla lo recorta por ARRIBA, y
        // arriba es justo donde va el nombre del ejercicio. Pasó en el reloj:
        // la lista de series se veía entera y el encabezado no existía.
        child: _inset == _centeredInset ? Center(child: child) : child,
      ),
    );
  }
}
