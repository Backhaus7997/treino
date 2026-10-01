import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático — el router de la app móvil no llega a Ajustes.
///
/// POR QUÉ EXISTE. La pestaña «Facturación TREINO» (`FacturacionTab`, adentro
/// de `/ajustes`) muestra una línea de estado de la cuenta: «Plan dado de baja.
/// Sigue activo hasta el d/m.». No es una invitación a pagar, y se escribió
/// sabiendo que la app móvil no puede llegar a esa pestaña. Si pudiera, esa
/// línea tendría que revisarse contra 3.1.3(f) (ver
/// `test/features/paywall/anti_steering_movil_test.dart`) antes de quedarse en
/// el binario de iOS.
///
/// Ese supuesto vivía en un comentario. Un comentario no se pone rojo el día
/// que alguien registra `/ajustes` en el router móvil —para que «Cuenta»
/// funcione en el teléfono, por ejemplo— y la línea llega a la tienda sin que
/// nadie la haya mirado.
///
/// LA REGLA. `lib/app/router.dart` es el router de la app móvil (el de
/// `main.dart`) y no menciona `ajustes` ni `FacturacionTab`. El Coach Hub web
/// tiene su propio entrypoint (`main_coach_hub.dart`) y su propio router
/// (`coach_hub_router.dart`), y ahí sí vive `/ajustes`.
///
/// Si de verdad hace falta una pantalla de ajustes en el teléfono, el camino no
/// es allowlistear esta aguja: es revisar qué muestra esa pestaña en móvil
/// (empezando por la línea de la baja) y recién entonces cambiar este guard.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que la pestaña sea inalcanzable. Un
/// scanner de texto jamás dice que algo FUNCIONA: dice que un patrón no está.
/// Mira UN archivo, sin comentarios, y no ve una ruta que llegue por otro
/// lado: un archivo importado por `router.dart` que registre `/ajustes`, o un
/// `FacturacionTab` montado desde otra pantalla de la app. Eso se caza en
/// review, igual que en los otros scanners de esta carpeta.
///
/// Por eso lleva un control: si el archivo no existe, o no tiene la ruta de la
/// pricing page (que SÍ viaja en el binario móvil), el guard falla en vez de
/// dar un verde sobre un archivo que ya no es el router.
void main() {
  group('router_movil_sin_ajustes_scan — la app móvil no llega a Facturación',
      () {
    const rutaDelRouter = 'lib/app/router.dart';

    /// Rutas y símbolos que NO pueden aparecer en el router móvil, en
    /// minúsculas (el texto se normaliza igual).
    const agujas = <String>['ajustes', 'facturaciontab'];

    late String codigo;

    setUpAll(() {
      final archivo = File(rutaDelRouter);
      expect(
        archivo.existsSync(),
        isTrue,
        reason: 'no encuentro $rutaDelRouter desde ${Directory.current}. Si se '
            'movió, mové también este guard en vez de borrarlo: sin el archivo '
            'daría un verde vacío.',
      );
      codigo = _sinComentarios(archivo).toLowerCase();
    });

    // El control del scanner. Sin esto, un router vaciado, o un path que
    // apunte a otro archivo, pasaría las agujas de abajo por no tener nada.
    test('control: lee el router móvil de verdad (tiene la pricing page)', () {
      expect(
        codigo,
        contains('/facturacion/planes'),
        reason: '$rutaDelRouter ya no registra /facturacion/planes, que es la '
            'ruta de la pricing page en el binario móvil '
            '(`router_paywall_pricing_route_test.dart`). Si dejó de ser el '
            'router de la app, este guard está mirando otra cosa.',
      );
    });

    for (final aguja in agujas) {
      test('el router móvil no menciona «$aguja»', () {
        expect(
          codigo.contains(aguja),
          isFalse,
          reason: '$rutaDelRouter menciona «$aguja»: la app móvil podría '
              'llegar a la pestaña Facturación de Ajustes.\n\n'
              'Esa pestaña muestra "Plan dado de baja. Sigue activo hasta el '
              'd/m." y está escrita para el Coach Hub web. Antes de exponerla '
              'en el teléfono hay que revisarla contra 3.1.3(f) (ver '
              '`anti_steering_movil_test.dart`).\n'
              'Si es un Ajustes propio de la app móvil y no tiene nada que ver '
              'con Facturación, nombrá la ruta distinto o hablalo antes de '
              'tocar este guard.',
        );
      });
    }
  });
}

/// El código de [f] sin comentarios de línea.
///
/// El router explica en prosa por qué no registra ciertas rutas, y nombrarlas
/// en una explicación no es registrarlas. Mismo criterio que los otros
/// scanners de esta carpeta. (Corta en el primer `//` de cada línea, también
/// dentro de un string: para estas agujas da igual.)
String _sinComentarios(File f) => f.readAsLinesSync().map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');
