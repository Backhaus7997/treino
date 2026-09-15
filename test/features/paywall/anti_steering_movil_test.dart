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
  'treino web',
  'desde la web',
  'en la web',
  'suscribite en',
  'contrata en',
  'contratar en',
];

/// El texto listo para buscarle una aguja: minúsculas y sin acentos.
///
/// ⚠️ **SIN ESTO EL GUARD MENTÍA, y se descubrió por mutación el 2026-09-15.**
///
/// Las agujas estaban escritas `'TREINO web'` y `'contratá en'`, y el cartel
/// que vivía en `pricing_screen.dart` decía **`'SE CONTRATA EN TREINO WEB'`**:
/// mayúsculas y sin tilde. Un `contains` es case-sensitive, así que ese cartel
/// —el del slot del CTA, el más visible de los tres— **nunca estuvo cubierto**.
/// El archivo figuraba en `declarados` por el cartel LARGO, y el corto viajaba
/// de arriba sin que nadie lo mirara.
///
/// Se verificó: reinyectando ese texto exacto, el guard quedaba VERDE.
///
/// Normalizar las dos puntas es lo que hace que la lista de agujas signifique
/// lo que uno cree que significa al leerla. Las agujas de arriba van en
/// minúsculas y sin acento por la misma razón.
String _normalizado(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

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
      // Los dos de DEUDA —`plan_limit_paywall.dart` y `pricing_screen.dart`—
      // se pagaron el 2026-09-15 y por eso ya no están en esta lista.
      //
      // El snackbar ahora dice el ESTADO de la cuenta («Tu suscripción está
      // pausada.») y las dos constantes de la pricing page quedaron VACÍAS,
      // que es exactamente lo que su propio dartdoc anticipaba para el caso de
      // «callarlo».
      //
      // ⚠️ Lo que se pagó con eso está escrito donde se pagó, y no se repite
      // acá para que no se desactualice: el PF que entró por el teléfono queda
      // sin saber dónde pagar. La salida es un MAIL, que es lo único que Apple
      // no gobierna — y todavía no existe.
      //
      // Éste NO era deuda y por eso se queda.
      //
      // Dice «Pausar la cuenta todavía no está disponible desde la web», que
      // habla de una función que falta, no de dónde se paga. Está acá sólo
      // porque comparte la aguja `desde la web`, y sacarlo del guard exigiría
      // agujas más finas que traerían más falsos negativos que los que evitan.
      'lib/features/coach_hub/presentation/sections/ajustes/tabs/cuenta_tab.dart':
          'NO es steering: habla de pausar la cuenta, no de pagar. Falso '
              'positivo de la aguja `desde la web`',
      // Éste APARECIÓ el 2026-09-15, y no porque alguien lo escribiera: lo
      // destapó arreglar la case-sensitivity de `_carteles`. Dice «EDITOR EN LA
      // WEB» —en mayúsculas, que es justo lo que el guard viejo no veía— y
      // venía pasando desapercibido desde siempre.
      //
      // Tampoco es steering: habla del EDITOR DE RUTINAS, no de pagar. Se
      // declara por el mismo criterio que el de arriba, y no se afina la aguja
      // por el mismo motivo.
      'lib/features/onboarding/presentation/custom_exercise_onboarding_art.dart':
          'NO es steering: «EDITOR EN LA WEB» habla de dónde se edita una '
              'rutina, no de dónde se paga. Falso positivo de `en la web`',
    };

    test('la lista de carteles es exactamente la declarada', () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        final codigo = _sinComentarios(f);
        final normalizado = _normalizado(codigo);
        if (_carteles.any(normalizado.contains)) {
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

    test('la deuda está en CERO y se queda en cero', () {
      // Un contador explícito, separado del guard de arriba, para que la deuda
      // tenga un número y no se diluya en una lista que también contiene un
      // falso positivo declarado.
      //
      // Estuvo en 2 hasta el 2026-09-15. Ahora que está en cero este test
      // cambia de trabajo: dejó de medir cuánto falta y pasó a ser un
      // **ratchet** — el que agregue el próximo cartel se entera acá, antes de
      // mandarlo, y no en el rechazo de review.
      final deuda = declarados.entries
          .where((e) => e.value.startsWith('DEUDA:'))
          .map((e) => e.key)
          .toList();

      expect(
        deuda,
        isEmpty,
        reason: 'volvió a haber carteles de steering declarados como deuda.\n'
            'No los agregues: bajo 3.1.3(f) este binario está amparado sólo '
            '«provided there is no purchasing inside the app, OR CALLS TO '
            'ACTION for purchase outside of the app», y ese amparo se cae solo '
            'el día que el alumno compre por IAP.\n\n'
            'Si de verdad hace falta avisarle al PF dónde pagar, se avisa POR '
            'MAIL. Adentro de la app, no.',
      );
    });
  });
}
