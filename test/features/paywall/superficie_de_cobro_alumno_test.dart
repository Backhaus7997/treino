// Guard de superficie de cobro — el lado del ALUMNO.
//
// ─── LEER ESTO PRIMERO: LA REGLA QUE PROTEGE CAMBIO ─────────────────────────
//
// Este archivo nacio defendiendo la Guideline **3.1.3(f)** (*Free Stand-alone
// App*): la app movil no vende nada ni linkea al checkout, el alumno paga en la
// web y el entitlement llega por Firestore.
//
// **Esa decision se revirtio.** El alumno paga por IAP (App Store + Google
// Play) via RevenueCat. El motivo esta en `docs/paywall-alumno-suelto.md`: la
// exencion 3.1.3(f) exige que la app sea companion de una *"paid web based
// tool"*, y para el ALUMNO no existe ninguna superficie web — solo el PF tiene
// Coach Hub. Sin web no habia exencion que invocar.
//
// El PF sigue cobrando por Mercado Pago desde la web, y eso NO cambia: ahi
// 3.1.3(f) aplica de verdad.
//
// ─── POR QUE ESTE ARCHIVO SE REESCRIBIO EN VEZ DE BORRARSE ──────────────────
//
// Porque cuando la decision se dio vuelta, **los guards no se pusieron rojos**.
// Verificado por mutacion, no razonado: se cableo `Purchases.purchasePackage`
// adentro de `lib/features/paywall/` y los cuatro tests siguieron verdes.
//
// La razon es que todos los guards de este archivo miraban APERTURA DE URL
// (`launchUrl`, `url_launcher`, `WebViewController`). RevenueCat no usa ninguna:
// habla por platform channel contra StoreKit y Play Billing. O sea que la
// arquitectura que el repo blindo a mano se podia revertir en silencio.
//
// Un guard que no se pone rojo cuando la decision que defiende se revierte no
// es un guard: es un archivo que miente. Por eso ahora hay un tercer eje —
// **quien puede COMPRAR**— que es el que faltaba.
//
// ─── LOS TRES EJES QUE ESTE ARCHIVO FIJA ────────────────────────────────────
//
//   1. El paywall del alumno no abre nada afuera de la app.
//      Sigue valiendo, y ahora por un motivo MAS fuerte: con IAP adentro, el
//      intro de 3.1.3 prohibe *"encourage users to use a purchasing method
//      other than in-app purchase"*, y la excepcion es solo para la storefront
//      de EEUU. Argentina no lo es.
//
//   2. El repo entero declara quien abre una URL. (allowlist)
//
//   3. **NUEVO**: el repo entero declara quien COMPRA. (allowlist)
//      Comprar adentro de la app es ahora lo correcto para el alumno, pero
//      tiene que pasar por los archivos declarados y por ningun otro. Sin esto,
//      cualquier pantalla puede disparar una compra y nadie se entera al
//      revisar el PR.
//
// ─── El costo de equivocarse ────────────────────────────────────────────────
//
// Del lado del PF, cobrar por afuera desde el binario movil es 3.1.3(c) y hoy
// no hay exencion que lo cubra. Del lado del alumno, una compra disparada desde
// un lugar no declarado es una que nadie reviso.
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
    const permitidos = <String, String>{
      // El PRIMER y por ahora UNICO punto de compra del alumno. Es un tipo
      // sellado: `AthleteCheckoutOnStore` tiene `start`, `AthleteCheckoutUnavailable`
      // no lo tiene, y los constructores son privados a la libreria — asi que
      // desde `lib/` la unica forma de conseguir la variante que cobra es
      // `resolveAthleteCheckout()`.
      //
      // Una PANTALLA no deberia entrar nunca a esta lista: tiene que llamar a
      // este archivo, no hablarle al SDK por su cuenta. Si estas por agregar
      // una, ese es el olor.
      'lib/features/paywall/application/athlete_checkout.dart':
          'la capacidad de comprar del alumno: `start` es el unico camino a un '
              'cobro del alumno en toda la app, y el uid entra por su firma',
    };

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

  group('quién puede ABRIR el paywall del alumno', () {
    // ─── Este grupo REEMPLAZA a «ningún call site pasa `onUpgrade`» ──────────
    //
    // Aquel fijaba el estado de entonces: la hoja de límite no dibujaba botón
    // porque el checkout del alumno no existía, y su comentario decía que
    // ponerse rojo el día del cableado era su función — el recordatorio de
    // leer 3.1.3 antes de decidir qué hacía el botón.
    //
    // El recordatorio se cobró: se leyó, y la decisión fue sacar `onUpgrade`
    // de la firma. Eran 8 call sites pasando la MISMA closure, o sea 8
    // lugares donde alguien podía pasar una distinta —una que abriera la
    // web— sin que el tipo sellado se enterara. Ahora la hoja mira
    // `athleteCheckoutProvider` y decide sola.
    //
    // Con el parámetro afuera, aquel test no vigilaba nada: pasaba por
    // construcción. Lo que SÍ hay que vigilar ahora es el otro extremo —
    // **desde dónde se llega a la pantalla que vende**.
    const permitidos = <String, String>{
      'lib/features/paywall/presentation/free_plan_limit_sheet.dart':
          'la hoja de límite: es el instante en que el tope muerde, y el '
              'único lugar donde hoy se ofrece comprar',
    };

    test('la lista de archivos que abren el paywall es la declarada', () {
      final encontrados = <String>{};
      for (final f in _dartsDe('lib')) {
        if (f.path.endsWith('athlete_paywall_screen.dart')) continue;
        final codigo = _sinComentarios(f);
        if (codigo.contains('AthletePaywallScreen')) {
          encontrados.add(f.path.replaceAll(r'\', '/'));
        }
      }

      final nuevos = encontrados.difference(permitidos.keys.toSet());
      expect(
        nuevos,
        isEmpty,
        reason: 'lugares nuevos que abren el paywall del alumno:\n'
            '${nuevos.join("\n")}\n\n'
            'No está prohibido — el alumno TIENE que poder comprar. Pero cada '
            'entrada nueva es una pantalla más que un revisor de Apple puede '
            'abrir, así que sumala acá con su razón y mirá que el contexto '
            'tenga sentido: el paywall se ofrece cuando el límite MUERDE, no '
            'porque sí.',
      );

      final desaparecidos = permitidos.keys.toSet().difference(encontrados);
      expect(
        desaparecidos,
        isEmpty,
        reason: 'estos ya no abren el paywall: sacalos de `permitidos`\n'
            '${desaparecidos.join("\n")}',
      );
    });

    test('`onUpgrade` no volvió a la firma de la hoja', () {
      // El parámetro se sacó a propósito. Si vuelve, vuelve con él la
      // posibilidad de que un call site pase una closure que abra otra cosa.
      final hoja = File(
        'lib/features/paywall/presentation/free_plan_limit_sheet.dart',
      );
      expect(hoja.existsSync(), isTrue);
      expect(
        _sinComentarios(hoja).contains('onUpgrade'),
        isFalse,
        reason: 'volvió `onUpgrade` a la hoja de límite. Antes de reponerlo: '
            'eran 8 call sites pasando la misma closure, y cada uno era un '
            'lugar donde se podía pasar otra. La hoja decide sola mirando '
            '`athleteCheckoutProvider`.',
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
