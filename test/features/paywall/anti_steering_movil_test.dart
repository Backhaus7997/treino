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
// ─── Era un ratchet con deuda; hoy es un ratchet en cero ────────────────────
//
// Este encabezado decia que los tres carteles estaban DECLARADOS abajo y no
// borrados, y que vaciarlos era una decision de producto sin resolver. **Se
// resolvio el 2026-09-15 (PR #1141): los tres estan vacios.** El deadline que
// este bloque nombraba —la primera submission de iOS con la suscripcion del
// alumno— dejo de ser una fecha a la que llegar.
//
// Asi que el test cambio de trabajo. Ya no mide cuanto falta: impide que
// reaparezca. El que agregue el proximo cartel se entera antes de mandarlo, y
// no en el rechazo de review.
//
// ─── Lo que ese cierre cuesta, que NO esta pago ─────────────────────────────
//
// El PF que entro por el telefono quedo sin saber donde pagar. Eso no se
// recupera adentro de la app —3.1.3(f) no lo permite— sino por MAIL, que es lo
// unico que Apple habilita explicitamente. Ese canal existe: son los tres mails
// del paywall (`subscription-grace`, `subscription-downgraded`, y
// `limit-reached` para el que nunca pago).
//
// Si alguien apaga ese ultimo mail, este ratchet sigue en cero y el funnel
// igual queda sin salida. El cero de abajo NO es la prueba de que el problema
// este resuelto: es la prueba de que no volvio a entrar por esta puerta.
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

/// Un ítem de la lista que el código YA desmiente.
///
/// [frase] se busca en el bloque de ítems ABIERTOS de
/// `athlete_entitlement.dart` (normalizada: minúsculas, sin acentos).
/// [marcador] se busca TAL CUAL en [archivo]. Si aparecen los dos, la lista
/// quedó vieja.
class _Contradiccion {
  const _Contradiccion(this.frase, this.archivo, this.marcador, this.porque);
  final String frase;
  final String archivo;
  final String marcador;
  final String porque;
}

const _contradicciones = <_Contradiccion>[
  _Contradiccion(
    'carteles de steering',
    'test/features/paywall/anti_steering_movil_test.dart',
    "startsWith('DEUDA:')",
    'la deuda de carteles se mide ahí y está en CERO (el test de más arriba).',
  ),
  _Contradiccion(
    'no lo mira nunca',
    'firestore.rules',
    'copiadaDelCatalogo',
    'el CREATE de `/routines` SÍ mira de dónde se copió una rutina, desde el '
        'PR #1155.',
  ),
];

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
      // no gobierna — y YA EXISTE: `limit-reached` (PR #1149).
      //
      // Esta línea decía «y todavía no existe», y era falso incluso cuando se
      // escribió: `subscription-grace` y `subscription-downgraded` ya estaban
      // deployados. Se corrigió el 2026-09-16 después de verificarlo, en vez de
      // seguir citando el cartel.
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

    test('la lista autoritativa del paywall no lo sigue dando por pendiente',
        () {
      // ─── POR QUÉ ESTE TEST EXISTE ───────────────────────────────────────
      //
      // Porque el mismo error pasó DOS VECES sobre el mismo archivo.
      //
      // `athlete_entitlement.dart` es la lista autoritativa que decide cuándo
      // se enciende el paywall — `docs/paywall-alumno-suelto.md` dice textual
      // que «la lista al día está acá». Y dos veces un ítem se quedó ahí
      // después de estar resuelto:
      //
      //   · el seed del catálogo, cerrado el 2026-09-14 y listado hasta el 15.
      //     Alguien arrancó a trabajarlo antes de verificar.
      //   · estos carteles, cerrados el 2026-09-15 (PR #1141) y listados hasta
      //     el 16 — cerrados por la MISMA persona que dejó el renglón.
      //
      // El archivo ya traía una advertencia escrita para que no se repitiera.
      // **No alcanzó**: una advertencia la lee el que ya se acordó. Por eso
      // ahora es un test.
      //
      // Lo que ata: si la deuda de ARRIBA está en cero, la lista NO puede
      // seguir nombrando estos carteles entre los ítems abiertos. Las dos
      // mitades se mueven juntas o esto se pone rojo.
      final lista = File(
        'lib/features/paywall/domain/athlete_entitlement.dart',
      ).readAsStringSync();

      // Sólo el bloque de ítems ABIERTOS. La sección de cerrados los nombra a
      // propósito —ahí es donde tienen que estar— así que mirar el archivo
      // entero haría que este test fallara justo cuando alguien hace lo
      // correcto.
      final desde = lista.indexOf('Lo que falta HOY');
      final hasta = lista.indexOf('Lo que SALIÓ de esta lista');
      expect(
        desde,
        isNot(-1),
        reason: 'no encontré el bloque «Lo que falta HOY» en la lista '
            'autoritativa. Si lo renombraste, actualizá este test: sin ese '
            'ancla deja de mirar nada y te da un verde vacío.',
      );
      expect(hasta, greaterThan(desde),
          reason: 'el bloque de cerrados tiene '
              'que venir DESPUÉS del de abiertos; si no, el recorte está al revés.');

      final abiertos = _normalizado(lista.substring(desde, hasta));

      // ─── LA TABLA, y por qué el guard dejó de cuidar UN ítem ────────────
      //
      // La primera versión de esto miraba una sola aguja: «carteles de
      // steering». Sirvió una vez y falló a la siguiente — el 2026-09-16 se
      // cerró el candado del catálogo (#1155) y el renglón se quedó en la
      // lista un día más, sin que nada chillara. Van TRES con esa forma: el
      // seed, los carteles, y el candado.
      //
      // El patrón real es más general: **cada ítem abierto afirma algo sobre
      // el código, y esa afirmación se puede desmentir leyendo el código.**
      // Si la lista dice «el servidor no mira las copias» y `firestore.rules`
      // tiene `copiadaDelCatalogo`, la lista miente y el test lo sabe.
      //
      // Agregar un ítem a la lista = agregar su fila acá. Es una línea.
      for (final c in _contradicciones) {
        if (!abiertos.contains(_normalizado(c.frase))) continue;
        final codigo = File(c.archivo).readAsStringSync();
        expect(
          codigo.contains(c.marcador),
          isFalse,
          reason:
              '`athlete_entitlement.dart` sigue listando como PENDIENTE algo '
              'que el código ya resolvió.\n\n'
              'Dice: «${c.frase}»\n'
              'Pero ${c.archivo} contiene `${c.marcador}` — ${c.porque}\n\n'
              'Movelo a la sección «Lo que SALIÓ de esta lista, y por qué». '
              'Una lista autoritativa equivocada es PEOR que no tener lista: '
              'manda a alguien a trabajar algo que ya está hecho, y con este '
              'archivo ya pasó tres veces.\n\n'
              'Y al moverlo, escribí lo que el cierre COSTÓ o dejó abierto. '
              'Un ítem que sale sin su precio es sólo una línea menos.',
        );
      }
    });
  });
}
