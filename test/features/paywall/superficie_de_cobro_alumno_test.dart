// Guard de superficie de cobro — el lado del ALUMNO.
//
// ─── LEER ESTO PRIMERO: LA REGLA CAMBIO DOS VECES ───────────────────────────
//
// Este archivo defendio dos decisiones opuestas y ahora vuelve a la primera.
// La historia importa, porque quien la ignore va a revertirla una tercera vez:
//
//   1. **El alumno paga por web.** Apoyado en la Guideline 3.1.3(f), que exime
//      del IAP a la app companion de una *"paid web based tool"*.
//   2. **El alumno paga por IAP.** Se revirtio porque para el ALUMNO no habia
//      ninguna superficie web de la cual ser companion: sin web no habia
//      exencion, y caia 3.1.1.
//   3. **El alumno paga por web, otra vez** — y ahora si existe la superficie:
//      `gettreino.com` tiene checkout, ingreso y baja. El IAP se desarmo
//      entero: `purchases_flutter` salio del binario con esta misma PR.
//
// El PF nunca dejo de cobrar por Mercado Pago desde el Coach Hub web.
//
// ─── LO QUE ESTE ARCHIVO FIJA HOY ───────────────────────────────────────────
//
//   1. **Nadie compra adentro de la app.** Ni el alumno ni el PF. La allowlist
//      de compras esta VACIA, y eso es la funcionalidad: el primero que cablee
//      un SDK de billing pone rojo este test.
//
//   2. **El paywall del alumno no abre nada afuera de la app.** Ni un
//      `launchUrl`, ni un WebView, ni una mencion de la landing.
//
//   3. **El repo entero declara quien abre una URL.** (allowlist)
//
// ─── El costo de equivocarse, que es lo que casi nadie ve ───────────────────
//
// La tentacion obvia es poner un boton que diga «suscribite en gettreino.com»
// cuando el alumno topa el limite. Parece inofensivo: no cobra nada adentro.
//
// Es lo peor que se puede hacer. 3.1.3 ampara el binario mientras no haya
// compras adentro **NI llamados a comprar afuera**. Ese boton no le cuesta
// plata al alumno: le cuesta la exencion **al ENTRENADOR**, que hoy es el
// unico ingreso real del producto.
//
// Por eso la app, cuando el limite muerde, dice que el limite mordio y nada
// mas. No hay CTA. No es un olvido.
//
// ─── Por que la version anterior de este archivo no sirvio ──────────────────
//
// Cuando la decision se dio vuelta la primera vez, **los guards no se pusieron
// rojos**. Verificado por mutacion: se cableo `Purchases.purchasePackage` y los
// cuatro tests siguieron verdes, porque todos miraban APERTURA DE URL y
// RevenueCat no usa ninguna — habla por platform channel.
//
// De ahi salio el eje de «quien COMPRA», que es el que ahora esta en cero.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// APIs que abren algo fuera de la app. Un CTA de compra necesita alguna.
const _aperturasExternas = <String>[
  'package:url_launcher',
  'launchUrl(',
  'launchUrlString(',
  'WebViewController',
  'WebViewWidget',
  'InAppBrowser',
];

/// APIs que disparan una compra dentro de la app.
///
/// El import solo ya alcanza —no se puede usar el SDK sin importarlo— pero los
/// metodos van igual: si algun dia el import se esconde detras de un barrel
/// propio, la llamada sigue siendo visible.
const _apisDeCompra = <String>[
  'package:purchases_flutter',
  'Purchases.purchasePackage',
  'Purchases.purchase(',
  'Purchases.purchaseProduct',
  'Purchases.purchaseStoreProduct',
  'package:in_app_purchase',
];

/// El código de [f] sin comentarios.
///
/// Sin esto el test se cae contra su propia documentación: los archivos del
/// paywall EXPLICAN en dartdoc por qué no puede haber un launcher, y nombrar
/// `launchUrl` en una explicación no es cablearlo. Es la misma lección que ya
/// aprendió el guard del entrenador.
///
/// Corta en el primer `//`, así que una línea con `launchUrl(Uri.parse(
/// 'https://…'))` queda truncada en `https:` — pero conserva el `launchUrl(`,
/// que es lo que se busca. No maneja comentarios de bloque `/* */`: no hay en
/// este repo, y si aparecen, el falso positivo es del lado seguro.
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
  group('el paywall del alumno no abre nada afuera de la app', () {
    final dir = Directory('lib/features/paywall');

    test('la carpeta existe donde este test la busca', () {
      expect(dir.existsSync(), isTrue,
          reason: 'no encontré lib/features/paywall desde ${Directory.current}'
              ' — si se movió, movete este test con ella en vez de borrarlo');
    });

    test('ningún archivo del paywall puede abrir el navegador', () {
      final hallazgos = <String>[];
      for (final f in _dartsDe('lib/features/paywall')) {
        final codigo = _sinComentarios(f);
        for (final aguja in _aperturasExternas) {
          if (codigo.contains(aguja)) hallazgos.add('${f.path}: $aguja');
        }
      }

      expect(
        hallazgos,
        isEmpty,
        reason: 'el paywall del alumno abre algo afuera de la app. Bajo la '
            'Guideline 3.1.3(f) la app no puede linkear al checkout — ni con '
            'un botón, ni desde el `onUpgrade` de la hoja de límite:\n'
            '${hallazgos.join("\n")}',
      );
    });
  });

  group('quién puede abrir una URL en toda la app', () {
    // Allowlist, y a propósito.
    //
    // El guard por carpeta no alcanza: el `onUpgrade` de la hoja lo puede
    // construir CUALQUIER call site —hoy `routine_editor_screen` y
    // `routine_detail_screen`—, y ahí un `launchUrl` a la pasarela queda
    // afuera del scope de `lib/features/paywall/`.
    //
    // Entonces la pregunta se da vuelta: en vez de "esta carpeta no abre
    // nada", **el repo entero declara quién abre**. Agregar un launcher nuevo
    // pone rojo este test, y el que lo agrega tiene que escribir acá por qué
    // su destino no es un punto de venta. Ese medio minuto es el punto.
    //
    // Mismo patrón que `scripts/test/storage_scripts_destination.test.js`:
    // cuando la garantía vive en un archivo que nadie mira al revisar un PR,
    // el test lo mira.
    const permitidos = <String, String>{
      'lib/features/workout/presentation/widgets/exercise_video_player.dart':
          'abre el video del ejercicio en el reproductor del sistema cuando '
              'el embebido no puede — contenido, no compra',
      'lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart':
          'sólo Coach Hub WEB: abre archivos del alumno. La regla de Apple '
              'no aplica a la web, y esta pantalla no viaja en el binario móvil',
      // Éste NO se puede justificar con el argumento del de arriba, y la
      // diferencia importa: es la pantalla del alumno y **sí viaja en el
      // binario móvil**.
      //
      // Lo que lo hace admisible es el destino. Abre el `downloadUrl` de un
      // archivo que su PF le compartió, y esa URL la genera
      // `getDownloadURL()` de Firebase Storage — contenido, nunca una compra.
      //
      // Pero eso último NO alcanzaba solo, y conviene decir por qué en vez de
      // afirmar que estaba cubierto: `downloadUrl` lo escribe el PF y la regla
      // de Firestore sólo valida que sea un string, así que un cliente
      // modificado podía poner ahí una pasarela de pago y el alumno la abría
      // de un tap. Por eso `_FileRow._open()` no abre nada que no venga de un
      // host de Storage. Ese chequeo es la garantía; este renglón sólo la
      // declara.
      'lib/features/coach/presentation/athlete_files_screen.dart':
          'abre el archivo que el PF le compartió al alumno. Viaja en móvil, '
              'pero `_open()` sólo lanza URLs con host de Firebase Storage '
              '(el `downloadUrl` lo escribe el PF y las rules no validan su '
              'forma) — contenido, no compra',
      // ⚠️ Éste es DISTINTO de los dos de arriba, y conviene tenerlo claro
      // antes de agregar el próximo con el mismo argumento.
      //
      // Los otros dos no son puntos de venta. Éste SÍ: abre el checkout de
      // Mercado Pago. Y a diferencia de `alumno_detail_screen`, este archivo
      // VIAJA EN EL BINARIO MÓVIL — la pricing page se muestra en móvil, en
      // modo informativo, así que la app lo compila.
      //
      // Lo que lo hace admisible no es dónde vive el archivo, es que la app
      // móvil NO PUEDE LLEGAR a esa línea: `launchUrl` está adentro de
      // `PlanCheckoutAvailable.start`, y en móvil `resolvePlanCheckout()`
      // devuelve `PlanCheckoutOnWebOnly`, que no expone `start`. Los
      // constructores son privados a la librería, así que no hay forma de
      // fabricar la otra variante desde `lib/`.
      //
      // Eso NO es una promesa: hay tres tests en `pricing_screen_test.dart`
      // que prueban que en móvil ningún tap llega a un punto de compra, y una
      // mutación que los pone en rojo si el sellado se rompe.
      //
      // Si algún día hace falta la garantía más fuerte —que el launcher ni
      // siquiera esté en el binario— el camino es un import condicional que
      // deje un stub en móvil. Hoy no se hizo porque el sellado ya lo cubre y
      // el import condicional agrega una superficie que también hay que testear.
      'lib/features/coach_hub/presentation/sections/facturacion_planes/plan_checkout.dart':
          'ÚNICO punto de compra de la app: abre el checkout de Mercado Pago. '
              'Viaja en el binario móvil pero es inalcanzable desde ahí — el '
              'tipo sellado no expone `start` en la superficie móvil. Ver el '
              'comentario de arriba y el encabezado de plan_checkout.dart',
    };

    test('la lista de archivos que abren URLs es exactamente la declarada', () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        final codigo = _sinComentarios(f);
        if (_aperturasExternas.any(codigo.contains)) {
          // Barras NORMALIZADAS a `/`. En Windows `File.path` usa `\`, así que
          // sin esto NINGUNA clave de `permitidos` matchea y el test falla
          // siempre — incluso sobre archivos que ya estaban declarados.
          //
          // Un guard que sólo se puede correr en Linux es un guard que te
          // enterás de que rompiste cuando ya perdiste el ciclo de CI.
          encontrados.add(f.path.replaceAll(r'\', '/'));
        }
      }

      final nuevos = encontrados.difference(permitidos.keys.toSet());
      expect(
        nuevos,
        isEmpty,
        reason: 'archivos nuevos abriendo algo afuera de la app:\n'
            '${nuevos.join("\n")}\n\n'
            'Si el destino NO es un punto de venta, sumalo a `permitidos` con '
            'su razón. Si LO ES, la app móvil no puede hacerlo: la Guideline '
            '3.1.3(f) la obliga a no linkear al checkout, y Argentina no está '
            'en el External Purchase Link Entitlement.',
      );

      final desaparecidos = permitidos.keys.toSet().difference(encontrados);
      expect(
        desaparecidos,
        isEmpty,
        reason: 'estos ya no abren nada: sacalos de `permitidos` para que la '
            'lista siga diciendo la verdad\n${desaparecidos.join("\n")}',
      );
    });
  });

  group('quién puede COMPRAR en toda la app', () {
    // El eje que faltaba, y el que dejo que la decision se revirtiera en
    // silencio. Mismo patron que la allowlist de URLs de arriba: en vez de
    // "esta carpeta no compra", **el repo entero declara quien compra**.
    //
    // Hoy la lista esta VACIA a proposito. No es un olvido: todavia no hay
    // ningun cableado de compra en `lib/`. El primero que lo agregue va a poner
    // rojo este test y va a tener que escribir aca por que ese archivo es un
    // punto de compra legitimo. Ese medio minuto es todo el punto.
    //
    // Cuando llegue el cableado, la lista deberia quedar corta: el bootstrap
    // que hace `Purchases.configure`, y el repositorio que dispara la compra.
    // Una pantalla NO deberia estar aca — deberia llamar al repositorio.
    // ⚠️ VACIA, y esa es la funcionalidad.
    //
    // Antes tenia una entrada: `revenuecat_store.dart`, el unico archivo que le
    // hablaba al SDK. Ese archivo se borro con el resto del IAP.
    //
    // El primero que cablee un SDK de billing en `lib/` va a poner rojo este
    // test y va a tener que escribir aca por que ese archivo es un punto de
    // compra legitimo. Ese medio minuto es todo el punto — y es exactamente el
    // medio minuto que falto la vez que la decision se revirtio en silencio.
    const permitidos = <String, String>{};

    test('la lista de archivos que compran es exactamente la declarada', () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        final codigo = _sinComentarios(f);
        if (_apisDeCompra.any(codigo.contains)) {
          encontrados.add(f.path.replaceAll(r'\', '/'));
        }
      }

      final nuevos = encontrados.difference(permitidos.keys.toSet());
      expect(
        nuevos,
        isEmpty,
        reason: 'archivos nuevos disparando una compra:\n'
            '${nuevos.join("\n")}\n\n'
            'Comprar adentro de la app es lo correcto para el ALUMNO, pero '
            'tiene que pasar por un lugar declarado. Sumalo a `permitidos` con '
            'su razón.\n\n'
            'Y si esto aparecio en una pantalla del PF: pará. El profe NO '
            'compra por IAP — paga por Mercado Pago desde la web, y meter su '
            'cobro adentro de la app le cambia la comision del 0% al 15%.',
      );

      final desaparecidos = permitidos.keys.toSet().difference(encontrados);
      expect(
        desaparecidos,
        isEmpty,
        reason: 'estos ya no compran: sacalos de `permitidos` para que la '
            'lista siga diciendo la verdad\n${desaparecidos.join("\n")}',
      );
    });
  });

  group('la pantalla que vendia ya no existe', () {
    // ─── Este grupo REEMPLAZA a «quien puede ABRIR el paywall del alumno» ────
    //
    // Aquel declaraba, con una allowlist, desde donde se llegaba a
    // `AthletePaywallScreen`. Tenia una entrada: la hoja de limite.
    //
    // Ya no hay pantalla que abrir. El alumno compra en `gettreino.com`, la app
    // no vende, y **tampoco puede decir donde se compra** — ver el encabezado.
    // Asi que la allowlist se convierte en su forma mas fuerte: cero.

    test('ningun archivo de lib/ nombra una pantalla de paywall', () {
      final encontrados = <String>[];
      for (final f in _dartsDe('lib')) {
        if (_sinComentarios(f).contains('AthletePaywallScreen')) {
          encontrados.add(f.path.replaceAll(r'\', '/'));
        }
      }

      expect(
        encontrados,
        isEmpty,
        reason: 'volvio una pantalla de compra a la app:\n'
            '${encontrados.join("\n")}\n\n'
            'Antes de reponerla: el alumno paga en gettreino.com. Una pantalla '
            'que venda adentro del binario rompe 3.1.3(f) y se lleva puesta la '
            'exencion del ENTRENADOR, que es el ingreso real de hoy.',
      );
    });

    test('la hoja de limite no ofrece comprar', () {
      // El instante en que el tope muerde es donde mas tienta poner un CTA.
      final hoja = File(
        'lib/features/paywall/presentation/free_plan_limit_sheet.dart',
      );
      expect(hoja.existsSync(), isTrue);

      final codigo = _sinComentarios(hoja);
      expect(
        codigo.contains('free_plan_limit_upgrade'),
        isFalse,
        reason: 'volvio el boton de comprar a la hoja de limite',
      );
      expect(
        codigo.contains('onUpgrade'),
        isFalse,
        reason: 'volvio `onUpgrade` a la hoja de limite. Antes de reponerlo: '
            'eran 8 call sites pasando la misma closure, y cada uno era un '
            'lugar donde se podia pasar otra.',
      );
    });
  });

  group('los guards de esta carpeta se normalizan bien', () {
    // ─── Por que existe este test ───────────────────────────────────────────
    //
    // Los guards de arriba comparan rutas contra una allowlist, y en Windows
    // `File.path` usa `\\`. Por eso todos normalizan con
    // `replaceAll(r'\\', '/')`.
    //
    // Escribir esa linea es sorprendentemente facil de arruinar: si la barra
    // invertida se pierde en el camino queda `replaceAll(r'', '/')`, o sea
    // patron VACIO, y Dart mete una barra entre CADA caracter. El path pasa a
    // ser `/l/i/b/...` y NINGUNA clave de la allowlist matchea.
    //
    // Lo peligroso es que el guard igual se pone rojo cuando corresponde, asi
    // que una prueba de mutacion lo da por bueno. Lo que se rompe es el
    // MENSAJE: el que lo dispare recibe un path ilegible y pierde diez minutos
    // entendiendo que le quisieron decir.
    //
    // Paso tres veces en un mismo dia. Tres veces es patron, no accidente.
    test('ningun replaceAll quedo con el patron vacio', () {
      final rotos = <String>[];
      for (final f in _dartsDe('test/features/paywall')) {
        if (f.path.endsWith('superficie_de_cobro_alumno_test.dart')) continue;
        if (f.readAsStringSync().contains("replaceAll(r'', ")) {
          rotos.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        rotos,
        isEmpty,
        reason: 'estos guards normalizan con un patron vacio, asi que su '
            'mensaje de error va a salir ilegible: ${rotos.join(", ")}',
      );
    });
  });
}
