import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Test de análisis estático: quién calcula `VigenciaDelPlan.de` en `lib/`.
///
/// POR QUÉ EXISTE. La vigencia es una foto: calculada en el build, no se
/// entera de que pasó la fecha de la baja, porque en ese instante no emite
/// nadie. `vigenciaDelPlanProvider` la recalcula sola en el borde, y las
/// pantallas que siguen calculándola en su build quedan nombradas en la
/// dartdoc «Una foto, no un reloj» de `plan_vigencia.dart`. Esa lista vivía
/// sólo en prosa, y git no la marca como conflicto: un PR que suma una
/// pantalla con `VigenciaDelPlan.de(...)` en el build no toca ese archivo, y
/// la lista queda mintiendo sin que nadie se entere.
///
/// LA REGLA, en las dos direcciones:
/// 1. Cada archivo de `lib/` que llama a `VigenciaDelPlan.de` en código (no
///    en comentarios) figura entre backticks en esa sección. El provider
///    también: es el que la calcula para los demás.
/// 2. Cada `*.dart` entre backticks de esa sección (salvo los `*_test.dart`)
///    sigue llamándola. Una pantalla que pasó al provider sale de la lista.
///
/// Los que leen el provider no llaman a `.de`, así que no necesitan figurar.
///
/// LO QUE ESTE SCANNER **NO** PRUEBA. Que una pantalla no mire el reloj por
/// otro lado: la dartdoc misma dice que hay pantallas que comparan
/// `currentPeriodEnd` contra su propio `now`. Tampoco ve un import con alias
/// (`as v` y `v.VigenciaDelPlan.de`) ni un tear-off guardado en una variable.
/// Mira texto, sin comentarios de línea.
///
/// Lleva controles para no dar un verde vacío: el archivo de la clase existe y
/// tiene la sección; el escaneo encuentra al provider, que sí o sí la llama; y
/// la regla, aplicada a un archivo inventado que la llama sin figurar, da una
/// violación.
void main() {
  const rutaDeLaClase = 'lib/features/coach/domain/plan_vigencia.dart';
  const titulo = '## Una foto, no un reloj';

  late Set<String> listados;
  late List<String> rutasQueLlaman;
  late Map<String, String> llamadores;

  setUpAll(() {
    final clase = File(rutaDeLaClase);
    expect(
      clase.existsSync(),
      isTrue,
      reason: 'no encuentro $rutaDeLaClase desde ${Directory.current}. Si se '
          'movió, mové también este guard en vez de borrarlo: sin el archivo '
          'daría un verde vacío.',
    );
    listados = archivosListados(clase.readAsLinesSync(), titulo: titulo);
    rutasQueLlaman = rutasQueLlamanDe(
      {
        for (final f in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          // En Windows `listSync` devuelve `lib\features\...`.
          f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
      },
      ignorar: {rutaDeLaClase},
    );
    llamadores = {for (final r in rutasQueLlaman) _nombre(r): r};
  });

  group('vigencia_en_el_build_scan — «Una foto, no un reloj» dice la verdad',
      () {
    test('control: la sección existe y nombra archivos', () {
      expect(
        listados,
        isNotEmpty,
        reason: '$rutaDeLaClase no tiene la sección «$titulo» o no nombra '
            'ningún archivo entre backticks.',
      );
    });

    test('control: el escaneo encuentra al provider', () {
      expect(
        llamadores.keys,
        contains('vigencia_del_plan_provider.dart'),
        reason: 'el provider calcula VigenciaDelPlan.de sí o sí. Si el escaneo '
            'no lo encuentra, está mirando otra carpeta o la regex dejó de '
            'matchear.',
      );
    });

    test('control: un llamador sin listar es una violación', () {
      final inventados = rutasQueLlamanDe(
        {'lib/x/pantalla_nueva.dart': 'final v = VigenciaDelPlan.de(sub);'},
        ignorar: const {},
      );
      expect(
        faltantes(
          llamadores: {for (final r in inventados) _nombre(r): r},
          listados: listados,
        ),
        ['pantalla_nueva.dart'],
      );
      // Y en un comentario no cuenta: nombrarla no es calcularla.
      expect(
        rutasQueLlamanDe(
          {'lib/x/doc.dart': '/// No usa [VigenciaDelPlan.de] a propósito.'},
          ignorar: const {},
        ),
        isEmpty,
      );
    });

    // La sección nombra archivos por su nombre, no por su ruta: dos llamadores
    // con el mismo nombre en carpetas distintas serían uno solo para la lista,
    // y el que figura taparía al otro.
    test('no hay dos llamadores con el mismo nombre de archivo', () {
      final repetidos = rutasQueLlaman
          .where((r) =>
              rutasQueLlaman.where((o) => _nombre(o) == _nombre(r)).length > 1)
          .toList()
        ..sort();
      expect(
        repetidos,
        isEmpty,
        reason: 'Estos archivos llaman a VigenciaDelPlan.de y comparten '
            'nombre, así que «$titulo» no los puede distinguir: $repetidos. '
            'Renombrá uno.',
      );
    });

    test('cada llamador de VigenciaDelPlan.de figura en la sección', () {
      final sinListar = faltantes(llamadores: llamadores, listados: listados);
      expect(
        sinListar,
        isEmpty,
        reason: 'Estos archivos calculan VigenciaDelPlan.de y no figuran en '
            '«$titulo» ($rutaDeLaClase):\n'
            '${sinListar.map((f) => '  ${llamadores[f]}').join('\n')}\n\n'
            'Calculada en el build, la vigencia no se entera de que venció la '
            'baja hasta un rebuild ajeno. Si la pantalla puede quedar abierta '
            'en ese borde, leé `vigenciaDelPlanProvider` (con `select`). Si '
            'de verdad tiene que calcularla, nombrala entre backticks en esa '
            'sección, con el porqué.',
      );
    });

    test('cada archivo de la sección sigue llamando a VigenciaDelPlan.de', () {
      final rancios = listados.difference(llamadores.keys.toSet()).toList()
        ..sort();
      expect(
        rancios,
        isEmpty,
        reason: '«$titulo» ($rutaDeLaClase) nombra archivos que ya no llaman '
            'a VigenciaDelPlan.de: $rancios. Si pasaron al provider, sacalos '
            'de la lista de los que calculan en el build (y sumalos en prosa a '
            'los que lo leen). Si se renombraron, actualizá el nombre.',
      );
    });
  });
}

/// Los `*.dart` entre backticks de la sección [titulo] de la dartdoc, sin los
/// `*_test.dart` (la sección nombra a este guard).
///
/// La sección va desde la línea `/// [titulo]` hasta el próximo `/// ##` o la
/// primera línea que no es dartdoc.
Set<String> archivosListados(List<String> lineas, {required String titulo}) {
  final inicio = lineas.indexWhere((l) => l.trim() == '/// $titulo');
  if (inicio == -1) return const {};
  final seccion = <String>[];
  for (final l in lineas.skip(inicio + 1)) {
    final t = l.trim();
    if (!t.startsWith('///') || t.startsWith('/// ##')) break;
    seccion.add(t);
  }
  return RegExp(r'`([\w/]+\.dart)`')
      .allMatches(seccion.join(' '))
      .map((m) => m.group(1)!.split('/').last)
      .where((f) => !f.endsWith('_test.dart'))
      .toSet();
}

/// Las rutas de los [fuentes] que llaman a `VigenciaDelPlan.de` fuera de
/// comentarios de línea. [ignorar] es la ruta de la clase, que declara el
/// factory.
List<String> rutasQueLlamanDe(
  Map<String, String> fuentes, {
  required Set<String> ignorar,
}) {
  final llamada = RegExp(r'\bVigenciaDelPlan\s*\.\s*de\b');
  return [
    for (final MapEntry(key: ruta, value: codigo) in fuentes.entries)
      if (!ignorar.contains(ruta) && llamada.hasMatch(_sinComentarios(codigo)))
        ruta,
  ];
}

String _nombre(String ruta) => ruta.split('/').last;

/// Los llamadores que no figuran en [listados], ordenados.
List<String> faltantes({
  required Map<String, String> llamadores,
  required Set<String> listados,
}) =>
    llamadores.keys.where((f) => !listados.contains(f)).toList()..sort();

/// [codigo] sin comentarios de línea (corta en el primer `//` de cada línea,
/// también dentro de un string: para esta aguja da igual). Mismo criterio que
/// los otros scanners del repo.
String _sinComentarios(String codigo) => codigo.split('\n').map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    }).join('\n');
