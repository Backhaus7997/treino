/// Registro de tipografías del gate visual (#761).
///
/// ## El defecto que esto arregla, medido
///
/// `flutter test` NO registra en el engine las familias declaradas en el
/// `FontManifest`, ni las que `google_fonts` resuelve del bundle. Medido acá,
/// "ENTRENAR HOY" a 40 px:
///
/// | Cómo se pide la fuente | Ancho | Qué rinde |
/// |---|---|---|
/// | `GoogleFonts.barlow()` | 279,8 px | Barlow real |
/// | `TextStyle(fontFamily: AppFonts.barlow)` | 480,0 px | **tofu** (Ahem) |
/// | `TextStyle(fontFamily: AppFonts.barlowCondensed)` | 480,0 px | **tofu** (Ahem) |
///
/// 480,0 es exactamente 12 caracteres × 40 px: la fuente de test de Flutter,
/// que pinta un rectángulo lleno por glifo.
///
/// La diferencia importa porque el Coach Hub pide las fuentes de las **dos**
/// maneras: el `TextTheme` sale de `google_fonts`, pero hay **108
/// `fontFamily:` literales** en `lib/features/coach_hub/` que apuntan a
/// `'Barlow'` y `'Barlow Condensed'` a mano. Sin este registro, la mayoría del
/// texto de cada golden es una fila de cajitas — y un baseline de cajitas no
/// detecta una regresión tipográfica, la consagra.
///
/// El camino de `google_fonts` tampoco sale gratis: registra cada variante
/// recién cuando alguien la pide, y de forma asincrónica. Eso lo cubre
/// [_warmGoogleFonts], que tiene su propia historia escrita.
///
/// Lo mismo con los íconos: `phosphor_flutter` declara sus TTF bajo `fonts:` en
/// su pubspec, y `MaterialIcons` viene del framework — ninguno de los dos queda
/// registrado por `flutter test`, así que también salen tofu.
///
/// ## De dónde salen los bytes
///
/// De `assets/fonts/` — **los mismos TTF que la app embebe**, leídos por
/// `rootBundle`. Hay una copia de Barlow en `test/fonts/` que usaba el harness
/// de evidencia viejo; no se usa acá a propósito: dos fuentes de bytes para la
/// misma tipografía son dos cosas que pueden divergir, y el día que
/// `assets/fonts/` se actualice el gate seguiría fotografiando la versión
/// vieja.
library;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Los TTF de Barlow Condensed, bajo los dos nombres de familia que el Coach
/// Hub pide (ver [loadGateFonts]).
const List<String> kCondensedTtf = [
  'assets/fonts/BarlowCondensed-Regular.ttf',
  'assets/fonts/BarlowCondensed-Medium.ttf',
  'assets/fonts/BarlowCondensed-SemiBold.ttf',
  'assets/fonts/BarlowCondensed-Bold.ttf',
];

/// Deja el proceso listo para fotografiar texto: registra Barlow, Barlow
/// Condensed, los tres estilos de Phosphor que usa `TreinoIcon`, MaterialIcons,
/// y precalienta las variantes de `google_fonts`.
///
/// Llamalo desde un `setUpAll` — [useGateEnvironment] ya lo hace.
Future<void> loadGateFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await _loadFamily(AppFonts.barlow, const [
    'assets/fonts/Barlow-Regular.ttf',
    'assets/fonts/Barlow-Medium.ttf',
    'assets/fonts/Barlow-SemiBold.ttf',
    'assets/fonts/Barlow-Bold.ttf',
  ]);

  await _loadFamily(AppFonts.barlowCondensed, kCondensedTtf);

  // El MISMO TTF, otra vez, bajo el nombre SIN espacio.
  //
  // No es redundancia: son dos familias distintas para el engine, y el Coach
  // Hub pide las dos. `GoogleFonts.barlowCondensed(fontWeight: w700)` devuelve
  // `fontFamily: 'BarlowCondensed_700'` con `fontFamilyFallback:
  // ['BarlowCondensed']` (google_fonts_base.dart:115-116) — ninguno de los dos
  // es `AppFonts.barlowCondensed`, que lleva espacio.
  //
  // Registrar el nombre de fallback es lo que vuelve esto ESTRUCTURAL en vez de
  // un parche por variante: cualquier peso que google_fonts todavía no haya
  // terminado de cargar cae acá y rinde bien igual. Sin esto, el título de la
  // ficha de alumno —único call-site que pide Condensed 700 directo— salía en
  // cajitas en el primer test de su archivo y bien en el segundo.
  //
  // `AppFonts.barlow` ya es `'Barlow'`, que coincide con el fallback de
  // `GoogleFonts.barlow()`, así que esa familia no necesita una segunda vuelta.
  await _loadFamily('BarlowCondensed', kCondensedTtf);

  // `TreinoIcon` (lib/core/widgets/treino_icon.dart) es la única puerta a los
  // íconos del kit y sólo usa estos tres estilos — Light, Thin y Duotone no
  // aparecen en ningún lado de `lib/`.
  //
  // El nombre de familia va YA PREFIJADO. `PhosphorFlatIconData` construye cada
  // `IconData` con `fontFamily: 'Phosphor<Estilo>'` + `fontPackage:
  // 'phosphor_flutter'`, y Flutter resuelve el nombre EFECTIVO como
  // `packages/<paquete>/<familia>` (`TextStyle._effectiveFontFamily` en el
  // SDK). Registrarlo pelado no lo encuentra y los íconos siguen en tofu
  // aunque el TTF esté cargado.
  const phosphorStyles = {
    'Regular': 'Phosphor.ttf',
    'Fill': 'Phosphor-Fill.ttf',
    'Bold': 'Phosphor-Bold.ttf',
  };
  for (final entry in phosphorStyles.entries) {
    await _loadFamily(
      'packages/phosphor_flutter/Phosphor${entry.key}',
      ['packages/phosphor_flutter/lib/fonts/${entry.value}'],
    );
  }

  // MaterialIcons. El kit dice `TreinoIcon` (Phosphor), pero el Coach Hub tiene
  // 35 `Icons.*` de Material vivos —la lupa de "Buscar conversación" en el chat
  // es uno— y el gate fotografía lo que la app rinde, no lo que debería rendir.
  // Sin registrarla, esos 35 salen como cajitas y el baseline consagra el
  // defecto. La inconsistencia de familia de íconos es un hallazgo aparte, no
  // algo que el gate deba maquillar.
  await _loadFamily('MaterialIcons', const ['fonts/MaterialIcons-Regular.otf']);

  await _warmGoogleFonts();
}

/// Fuerza las cargas diferidas de `google_fonts` y **espera** a que terminen.
///
/// ## El defecto que esto arregla
///
/// `google_fonts` no registra una familia hasta que alguien pide ese estilo, y
/// la carga es fire-and-forget: el primer `paint` usa el fallback y recién un
/// rebuild posterior muestra la fuente real. En la app no se nota. En un golden
/// sí, y de la peor manera:
///
/// > **el PRIMER test de cada archivo salía con el texto del tema en tofu, y el
/// > resto bien.**
///
/// Reproducido byte a byte: dos corridas seguidas de la ficha de alumno daban
/// el mismo sha256, con `alumno-detail__dark` (primer test del archivo) en
/// cajitas y `alumno-detail__light` (segundo) correcto. No es una carrera —
/// es orden, y por eso da igual todas las veces. Un baseline así se hornea sin
/// que nadie lo note.
///
/// Construir los dos temas dispara las cargas; `pendingFonts()` las espera.
/// Corre en `setUpAll`, fuera del fake-async del `testWidgets`, así que el
/// `await` avanza de verdad.
Future<void> _warmGoogleFonts() async {
  // Construir los temas cubre lo que sale del `TextTheme`…
  AppTheme.dark();
  AppTheme.light();

  // …pero NO los pesos que la app aplica con `copyWith` después de que
  // google_fonts resolvió: `AppTheme._buildTextTheme` pide el Condensed en su
  // peso base y recién ahí lo pasa a w700, así que la variante
  // `BarlowCondensed_700` nunca se solicita durante el armado del tema. El
  // único call-site que la pide directo es el título de la ficha de alumno, y
  // por eso era la única que salía en cajitas.
  //
  // Se piden explícitamente los tres pesos que declara `AppFonts` sobre las dos
  // familias. Es una lista corta y cerrada porque la escala de pesos del design
  // system también lo es.
  for (final weight in const [
    FontWeight.w400,
    FontWeight.w600,
    FontWeight.w700,
  ]) {
    GoogleFonts.barlow(fontWeight: weight);
    GoogleFonts.barlowCondensed(fontWeight: weight);
  }

  await GoogleFonts.pendingFonts();
}

Future<void> _loadFamily(String family, List<String> assetPaths) async {
  final loader = FontLoader(family);
  for (final path in assetPaths) {
    // Sin try/catch a propósito: un asset que no está es un error del gate, no
    // un caso a tolerar. Tragarlo devolvería goldens en tofu que pasan.
    loader.addFont(rootBundle.load(path));
  }
  await loader.load();
}

/// Prueba que las familias literales quedaron registradas, midiendo.
///
/// ## Por qué hace falta un test aparte
///
/// **Las aserciones semánticas del gate NO detectan tofu.** `find.text('Mateo
/// García')` matchea el string del árbol de widgets: si la familia no está
/// registrada, el texto sigue estando y sólo cambian los glifos. O sea que una
/// regresión tipográfica pasa entera por el candado semántico y se hornea en el
/// baseline como si nada.
///
/// No es hipotético: pasó construyendo este gate. Restaurar un backup viejo
/// desarmó el `setUpAll` de fuentes y las doce capturas salieron en cajitas —
/// con los quince tests igual de verdes. Lo único que lo delató fue mirar los
/// PNG.
///
/// Por eso esto mide en vez de confiar. Corre como test con nombre, así CI dice
/// *"las tipografías del gate están registradas"* en rojo, en vez de doce diffs
/// de imagen que no explican nada.
void testGateFontsAreRegistered() {
  test('las tipografías del gate están registradas (no hay tofu)', () {
    const probe = 'ENTRENAR HOY';
    const size = 40.0;

    // La fuente de test de Flutter pinta un cuadrado LLENO de `size` × `size`
    // por glifo, así que su ancho es exactamente `probe.length * size`. Barlow
    // Condensed 700 mide ~216 px acá. El umbral al 90 % del ancho monoespaciado
    // deja lugar para cualquier tipografía real y sigue atrapando el fallback.
    const fallbackWidth = probe.length * size;

    void expectNotTofu(String label, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: probe, style: style.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();

      expect(
        width,
        lessThan(fallbackWidth * 0.9),
        reason:
            '"$probe" en $label midió ${width.toStringAsFixed(1)} px contra '
            '$fallbackWidth px del fallback de flutter_test. Está rindiendo en '
            'tofu. Revisá que el group llame a useGateEnvironment(), que '
            'assets/fonts/ tenga los TTF, y —si es una variante de '
            'google_fonts— que _warmGoogleFonts la esté pidiendo.',
      );
    }

    // 1) Las familias literales. 'BarlowCondensed' sin espacio va aparte: es el
    //    fallback de google_fonts y se rompe por separado de la que declara
    //    AppFonts (con espacio).
    for (final family in const [
      AppFonts.barlow,
      AppFonts.barlowCondensed,
      'BarlowCondensed',
    ]) {
      expectNotTofu(
        family,
        TextStyle(fontFamily: family, fontWeight: FontWeight.w700),
      );
    }

    // 2) Las variantes de google_fonts, peso por peso.
    //
    // Esto es lo que atrapa el defecto REAL que costó encontrar: el título de
    // la ficha de alumno pide `GoogleFonts.barlowCondensed(fontWeight: w700)`
    // directo, una variante que el armado del tema nunca solicita. Medir sólo
    // las familias literales de arriba la daba por buena mientras el golden
    // salía en cajitas.
    for (final weight in const [
      FontWeight.w400,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      final w = weight.value;
      expectNotTofu(
          'GoogleFonts.barlow(w$w)', GoogleFonts.barlow(fontWeight: weight));
      expectNotTofu(
        'GoogleFonts.barlowCondensed(w$w)',
        GoogleFonts.barlowCondensed(fontWeight: weight),
      );
    }
  });
}
