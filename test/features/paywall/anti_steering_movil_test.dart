// Guard anti-steering — el binario MOVIL entero, los dos productos.
//
// ─── Que regla protege ──────────────────────────────────────────────────────
//
// El intro de la Guideline 3.1.3 de Apple, textual (verificado el 2026-09-10
// contra el HTML vivo de las App Store Review Guidelines):
//
//   «Apps in this section cannot, within the app, encourage users to use a
//   purchasing method other than in-app purchase, **except for apps on the
//   United States storefront** and as set forth in 3.1.1(a) and 3.1.3(a).»
//
// Argentina no es la storefront de EEUU. Y la exencion que hoy ampara el cobro
// web del PF —la 3.1.3(f)— tiene su propia condicion, tambien textual:
//
//   «Free apps acting as a stand-alone companion to a paid web based tool
//   [...] do not need to use in-app purchase, **provided there is no purchasing
//   inside the app, or calls to action for purchase outside of the app**.»
//
// Son DOS condiciones, y la segunda es la que este archivo cuida: **no alcanza
// con no linkear. Un cartel que dice donde se paga YA es un call to action.**
//
// ─── Por que aparece recien ahora ───────────────────────────────────────────
//
// Porque el dia que el ALUMNO compre por IAP, la app deja de ser una *"free
// app [...] provided there is no purchasing inside the app"*. La exencion
// 3.1.3(f) deja de aplicarle a ese binario por su propio texto, y los carteles
// del PF se quedan sin nada que los ampare.
//
// El comentario que hoy vive al lado de uno de esos carteles dice: «no navega,
// no linkea y no abre nada: si algun dia esto arranca un cobro, es 3.1.3(c)».
// El razonamiento miraba el COBRO. La clausula que muerde es la de los *calls
// to action*, y esa no necesita que abras nada: alcanza con decirlo.
//
// ─── Por que es un ratchet y no un rojo ─────────────────────────────────────
//
// Los tres carteles que hay hoy estan DECLARADOS abajo, no borrados. Que digan
// o no digan es una decision de producto —¿que le muestra la app movil al PF
// que choco el limite?— y no se resuelve dentro de un test.
//
// Lo que el test SI garantiza es que la lista no CREZCA. El que agregue el
// cuarto cartel se entera antes de mandarlo, no despues del rechazo.
//
// ─── Cuando hay que vaciar la lista ─────────────────────────────────────────
//
// **Antes de la primera submission de iOS que incluya la suscripcion del
// alumno.** Ese es el momento exacto en que un revisor humano abre estas
// pantallas y las mira en serio, y es el unico deadline real que tiene esta
// deuda.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Frases que le dicen al usuario que vaya a pagar a otro lado.
///
/// No pretende ser exhaustiva: nadie puede enumerar todas las formas de decir
/// «pagá en la web» en castellano. Su trabajo no es atrapar al malicioso, es
/// frenar al distraido — el que copia un cartel existente sin saber que hay una
/// guideline atras.
///
/// Si agregas una frase nueva que este guard no atrapa, el problema no es el
/// guard: es que no leiste 3.1.3 antes de escribirla.
const _carteles = <String>[
  'TREINO web',
  'desde la web',
  'en la web',
  'suscribite en',
  'contratá en',
  'contratar en',
];

/// El código de [f] sin comentarios.
///
/// Los archivos del paywall EXPLICAN en dartdoc por que no puede haber un CTA
/// de compra externa, y nombrar la frase en una explicacion no es mostrarla.
/// Misma leccion que ya aprendieron los otros dos guards de esta carpeta.
String _sinComentarios(File f) => f.readAsLinesSync().map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');

List<File> _dartsDe(String ruta) => Directory(ruta)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('el binario móvil no dice dónde pagar por afuera', () {
    // Los tres carteles de hoy. Declarados, no perdonados.
    //
    // Los tres viven en `coach_hub/`, que a primera vista parece web-only y
    // por lo tanto fuera del alcance de Apple. **No lo es**: `router.dart:362`
    // lo dice textual — «`trainer_coach_view` son moviles, y su CTA "VER
    // PLANES" navega aca». La pricing page y el modal de limite se muestran en
    // el telefono, en modo informativo, asi que viajan en el binario.
    //
    // Que la carpeta se llame `coach_hub` no los saca de iOS.
    const declarados = <String, String>{
      'lib/features/coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart':
          'DEUDA: dos veces «Regularizá tu suscripción desde TREINO web.» — '
              'es un call to action bajo 3.1.3(f). Tiene que salir antes de la '
              'primera submission con IAP del alumno',
      'lib/features/coach_hub/presentation/sections/facturacion_planes/pricing_screen.dart':
          'DEUDA: «El alta y el cambio de plan se hacen desde TREINO web» — '
              'mismo problema, misma fecha límite',
      // Éste NO es deuda y no comparte el destino de los dos de arriba.
      //
      // Dice «Pausar la cuenta todavía no está disponible desde la web», que
      // habla de una función que falta, no de dónde se paga. Está acá sólo
      // porque comparte la aguja `desde la web`, y sacarlo del guard exigiría
      // agujas más finas que traerían más falsos negativos que los que evitan.
      'lib/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart':
          'NO es steering: habla de pausar la cuenta, no de pagar. Falso '
              'positivo de la aguja `desde la web`',
    };

    test('la lista de carteles es exactamente la declarada', () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        final codigo = _sinComentarios(f);
        if (_carteles.any(codigo.contains)) {
          // Barras normalizadas: en Windows `File.path` usa `\`, y sin esto
          // ninguna clave matchea y el guard falla siempre.
          encontrados.add(f.path.replaceAll(r'\', '/'));
        }
      }

      final nuevos = encontrados.difference(declarados.keys.toSet());
      expect(
        nuevos,
        isEmpty,
        reason: 'cartel nuevo diciendo dónde pagar, en código que viaja en el '
            'binario móvil:\n${nuevos.join("\n")}\n\n'
            'Bajo el intro de 3.1.3, la app no puede «encourage users to use a '
            'purchasing method other than in-app purchase» — y la excepción es '
            'sólo para la storefront de EEUU. Argentina no lo es.\n\n'
            'Si de verdad hace falta avisar dónde se paga: se avisa POR MAIL. '
            'Apple lo permite explícitamente («Developers can send '
            'communications outside of the app to their user base about '
            'purchasing methods other than in-app purchase»). Adentro de la '
            'app, no.',
      );

      final desaparecidos = declarados.keys.toSet().difference(encontrados);
      expect(
        desaparecidos,
        isEmpty,
        reason: 'estos ya no tienen carteles: sacalos de `declarados`.\n'
            'Si es porque se pagó la deuda, mejor todavía — borrá también el '
            'renglón y su comentario.\n${desaparecidos.join("\n")}',
      );
    });

    test('la deuda no creció: siguen siendo dos los archivos a limpiar', () {
      // Un contador explícito, separado del guard de arriba, para que la deuda
      // tenga un número y no se diluya en una lista que también contiene un
      // falso positivo declarado.
      final deuda = declarados.entries
          .where((e) => e.value.startsWith('DEUDA:'))
          .map((e) => e.key)
          .toList();

      expect(
        deuda,
        hasLength(2),
        reason: 'cambió la cantidad de archivos con carteles de steering.\n'
            'Si SUBIÓ: no agregues carteles nuevos, leé 3.1.3 primero.\n'
            'Si BAJÓ: bien ahí — bajá este número y borrá el renglón.',
      );
    });
  });
}
