// Genera las insignias de rango de levantamiento de `assets/ranking_ranks/`.
//
// ─── Qué dibuja ──────────────────────────────────────────────────────────────
//
// Ocho hexágonos, de Bronce (rango 1) a Olímpico (rango 8), más `unranked.svg`
// para "todavía sin rango". La idea es "la barra se va cargando": cada insignia
// lleva una barra con un disco más por lado que la anterior.
//
//   - Los discos van pegados a las puntas, con el mango a la vista en el medio,
//     y el apilado crece hacia el centro: un solo disco ancho en Bronce, ocho en
//     Olímpico. Un disco robusto en cada punta y un mango largo es lo que hace
//     que Bronce se lea como una barra y no como dos rayas dentro del hexágono,
//     que fue lo que pasó cuando los discos arrancaban pegados al centro.
//   - El ancho del apilado crece de a poco con el rango (8,75 con un disco, 21
//     con ocho), así que a tamaño chico la silueta se ensancha y a tamaño grande
//     se cuentan los discos. Los más bajos van hacia afuera, como en una barra
//     real: el apilado queda escalonado.
//   - El marco gana detalles con el rango (anillo, remaches, facetas, estrella,
//     puntas), así que el rango NO depende sólo del color: también se lee por la
//     cantidad de discos y por la silueta.
//
// ─── Por qué generadas y no dibujadas a mano ─────────────────────────────────
//
// Son ocho dibujos que comparten una geometría. A mano, retocar un disco o una
// sombra son ocho ediciones que tarde o temprano divergen. Acá hay una plantilla
// y ocho paletas: cambiar un número cambia la familia entera.
//
// Es el mismo esquema que `tool/build_legal_pages.dart`: este archivo es la
// fuente, los SVG son artefactos que SE COMMITEAN, y un test
// (`test/features/gym_rankings/lift_rank_badges_sync_test.dart`) falla si
// alguien edita uno a mano o toca el generador y olvida correrlo.
//
// ─── Uso ─────────────────────────────────────────────────────────────────────
//
//     dart run tool/build_lift_rank_badges.dart
//
// Reescribe `assets/ranking_ranks/*.svg`.
//
// Los colores son LITERALES a propósito. Son ilustraciones con materiales fijos
// (bronce, plata, oro…) que no cambian con el tema, igual que `treino_logo.svg`;
// el escaneo de hex literales (`no_hex_scan_test`) sólo mira `.dart` bajo `lib/`.

import 'dart:io';

const _outDir = 'assets/ranking_ranks';

const _banner =
    '<!-- Generado por tool/build_lift_rank_badges.dart. No editar a mano: '
    'dart run tool/build_lift_rank_badges.dart -->';

// Hexágono con la punta arriba: borde, banda, cara, anillo y aro exterior.
const _hexOuter = '0,-44 38.1,-22 38.1,22 0,44 -38.1,22 -38.1,-22';
const _hexBand = '0,-41 35.5,-20.5 35.5,20.5 0,41 -35.5,20.5 -35.5,-20.5';
const _hexFace = '0,-36 31.2,-18 31.2,18 0,36 -31.2,18 -31.2,-18';
const _hexRing = '0,-33 28.6,-16.5 28.6,16.5 0,33 -28.6,16.5 -28.6,-16.5';
const _hexAura = '0,-50 43.3,-25 43.3,25 0,50 -43.3,25 -43.3,-25';

/// Centros de los seis remaches, sobre la banda del hexágono.
const _rivetCenters = <(double, double)>[
  (0, -40.5),
  (35, -20.25),
  (35, 20.25),
  (0, 40.5),
  (-35, 20.25),
  (-35, -20.25),
];

/// Borde exterior del apilado de discos, pegado al collarín (que empieza en
/// 25.7). El apilado crece desde ahí hacia el centro.
const _stackOuter = 25.4;

/// Separación entre discos, y alto del disco más cercano al mango (el resto
/// baja [_plateStep] por cada puesto hacia afuera).
const _plateGap = 0.3;
const _plateTallest = 40.0;
const _plateStep = 3.4;

/// Ancho del apilado de [rank] discos: 8,75 con uno, 21 con ocho. Crece de a
/// poco para que el mango siga a la vista aun con la barra cargada.
double _stackWidth(int rank) => 7 + 1.75 * rank;

/// Discos del lado derecho de la insignia de [rank], de adentro hacia afuera,
/// como `(x, ancho, alto)`; el lado izquierdo es el espejo.
///
/// El ancho de cada disco sale de repartir el apilado entre los [rank] discos:
/// con uno es un bloque de 8,75 (se lee a tamaño chico) y con ocho son discos de
/// 2,4 separados por una línea (se cuentan a tamaño grande).
List<(double, double, double)> _platesFor(int rank) {
  final stack = _stackWidth(rank);
  final width = (stack - _plateGap * (rank - 1)) / rank;
  return [
    for (var j = 0; j < rank; j++)
      (
        _stackOuter - stack + j * (width + _plateGap),
        width,
        _plateTallest - _plateStep * j,
      ),
  ];
}

/// Rango máximo: cantidad de discos por lado, de insignias y de paletas.
const kLiftRankBadgeCount = 8;

/// Nombre de archivo de cada rango, de 1 (Bronce) a 8 (Olímpico), sin `.svg`.
const kLiftRankBadgeNames = <String>[
  'bronze',
  'silver',
  'gold',
  'platinum',
  'diamond',
  'champion',
  'titan',
  'olympian',
];

/// Puntas triangulares sobre los seis vértices: `tip` es el radio de la punta.
/// Titán usa 54 y Olímpico 58.
const _spikes54 = <String>[
  '0,-54 6,-42 -6,-42',
  '46.76,-27 39.37,-15.8 33.37,-26.2',
  '46.76,27 33.37,26.2 39.37,15.8',
  '0,54 -6,42 6,42',
  '-46.76,27 -39.37,15.8 -33.37,26.2',
  '-46.76,-27 -33.37,-26.2 -39.37,-15.8',
];
const _spikes58 = <String>[
  '0,-58 6,-42 -6,-42',
  '50.2,-29 39.37,-15.8 33.37,-26.2',
  '50.2,29 33.37,26.2 39.37,15.8',
  '0,58 -6,42 6,42',
  '-50.2,29 -39.37,15.8 -33.37,26.2',
  '-50.2,-29 -33.37,-26.2 -39.37,-15.8',
];

class _Look {
  const _Look({
    required this.rim,
    required this.face,
    required this.light,
    required this.dark,
    String? rimStroke,
    String? band,
    this.bandOpacity = '.5',
    this.bevelOpacity = '.7',
    this.facetOpacity = '.2',
    String? rivet,
    String? rivetStroke,
    this.ring = false,
    this.rivets = false,
    this.facets = false,
    this.star = false,
    this.spikes,
    this.spikeFill,
    this.spikeStroke,
    this.aura,
  })  : rimStroke = rimStroke ?? dark,
        band = band ?? light,
        rivet = rivet ?? light,
        rivetStroke = rivetStroke ?? dark;

  /// Borde del hexágono y color de la cara.
  final String rim;
  final String face;

  /// Tono claro (barra, brillos) y oscuro (discos, contornos) de la familia.
  final String light;
  final String dark;

  final String rimStroke;
  final String band;
  final String bandOpacity;
  final String bevelOpacity;
  final String facetOpacity;
  final String rivet;
  final String rivetStroke;

  final bool ring;
  final bool rivets;
  final bool facets;
  final bool star;

  /// Puntas sobre los vértices, con su relleno y su trazo.
  final List<String>? spikes;
  final String? spikeFill;
  final String? spikeStroke;

  /// Color del aro exterior, sólo en Olímpico.
  final String? aura;
}

/// Una paleta por rango, de Bronce a Olímpico. Colores literales: materiales
/// fijos que no cambian con el tema.
const _looks = <_Look>[
  // 1 Bronce: sólo la base.
  _Look(
    rim: '#9C5A2E',
    face: '#C98450',
    light: '#F0BE90',
    dark: '#4F2813',
  ),
  // 2 Plata: anillo.
  _Look(
    rim: '#7B8590',
    face: '#BCC4CD',
    light: '#EEF2F5',
    dark: '#3F464E',
    ring: true,
  ),
  // 3 Oro: remaches.
  _Look(
    rim: '#B7820F',
    face: '#EDBB2C',
    light: '#FFE98F',
    dark: '#5E4005',
    rivets: true,
  ),
  // 4 Platino: remaches + anillo.
  _Look(
    rim: '#23867E',
    face: '#55C9BB',
    light: '#B5F4EA',
    dark: '#0C423E',
    ring: true,
    rivets: true,
  ),
  // 5 Diamante: facetas + anillo.
  _Look(
    rim: '#4455CF',
    face: '#8392F7',
    light: '#CDD3FF',
    dark: '#1F2A78',
    ring: true,
    facets: true,
  ),
  // 6 Campeón: facetas + anillo + estrella.
  _Look(
    rim: '#8231B0',
    face: '#B85FE0',
    light: '#E9BDF8',
    dark: '#43125E',
    ring: true,
    facets: true,
    star: true,
  ),
  // 7 Titán: puntas oscuras + remaches + anillo.
  _Look(
    rim: '#8A1A1A',
    face: '#D8433B',
    light: '#FFA79C',
    dark: '#3B0707',
    ring: true,
    rivets: true,
    spikes: _spikes54,
    spikeFill: '#4A0C0C',
    spikeStroke: '#2A0505',
  ),
  // 8 Olímpico: aro y puntas doradas + facetas + anillo + remaches.
  _Look(
    rim: '#E2A416',
    rimStroke: '#6B4400',
    face: '#22BBE0',
    light: '#C4F5FF',
    dark: '#0A3C4F',
    band: '#FFE08A',
    bandOpacity: '.6',
    bevelOpacity: '.8',
    facetOpacity: '.25',
    rivet: '#FFC83D',
    rivetStroke: '#6B4400',
    ring: true,
    rivets: true,
    facets: true,
    spikes: _spikes58,
    spikeFill: '#FFC83D',
    spikeStroke: '#6B4400',
    aura: '#FFC83D',
  ),
];

/// `.5` en vez de `0.5` y `40` en vez de `40.0`: los mismos números que se ven en
/// el SVG, sin ruido de punto flotante.
String _n(double v) {
  final s = v.toStringAsFixed(2);
  final trimmed = s.contains('.')
      ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : s;
  return trimmed == '-0' ? '0' : trimmed;
}

/// Un rectángulo de disco como subtrazado, del lado derecho (`side = 1`) o del
/// izquierdo (`side = -1`).
String _platePath((double, double, double) plate, int side) {
  final (x, w, h) = plate;
  final left = side == 1 ? x : -(x + w);
  return 'M${_n(left)} ${_n(-h / 2)}h${_n(w)}v${_n(h)}h${_n(-w)}z';
}

String _platesPath(Iterable<(double, double, double)> plates) => [
      for (final p in plates) _platePath(p, 1),
      for (final p in plates) _platePath(p, -1),
    ].join(' ');

String _badge(int rank) {
  final look = _looks[rank - 1];
  final lines = <String>[];
  void add(String s) => lines.add('  $s');

  if (look.aura != null) {
    add('<polygon points="$_hexAura" fill="none" stroke="${look.aura}" '
        'stroke-width="1.5" stroke-linejoin="round"/>');
  }
  if (look.spikes != null) {
    add('<g fill="${look.spikeFill}" stroke="${look.spikeStroke}" '
        'stroke-width=".8" stroke-linejoin="round">');
    for (final s in look.spikes!) {
      add('  <polygon points="$s"/>');
    }
    add('</g>');
  }

  // Sombra, borde, banda y cara.
  add('<polygon points="$_hexOuter" transform="translate(0,2)" fill="#000" '
      'opacity=".2"/>');
  add('<polygon points="$_hexOuter" fill="${look.rim}" '
      'stroke="${look.rimStroke}" stroke-width="1.4" stroke-linejoin="round"/>');
  add('<polygon points="$_hexBand" fill="none" stroke="${look.band}" '
      'stroke-width=".7" opacity="${look.bandOpacity}"/>');
  add('<polygon points="$_hexFace" fill="${look.face}"/>');
  add('<path d="M-31.2 -18L0 -36L31.2 -18V0H-31.2z" fill="#fff" '
      'opacity=".1"/>');
  add('<path d="M-31.2 0H31.2V18L0 36L-31.2 18z" fill="#000" opacity=".08"/>');

  if (look.facets) {
    add('<path d="M0 -36L31.2 -18L0 0z M0 36L-31.2 18L0 0z" fill="#fff" '
        'opacity="${look.facetOpacity}"/>');
    add('<path d="M-31.2 -18L0 -36L0 0z M31.2 18L0 36L0 0z" fill="#000" '
        'opacity=".08"/>');
  }

  // Biseles: claro arriba a la izquierda, oscuro abajo a la derecha.
  add('<polyline points="-31.2,18 -31.2,-18 0,-36 31.2,-18" fill="none" '
      'stroke="${look.light}" stroke-width="1.6" stroke-linejoin="round" '
      'opacity="${look.bevelOpacity}"/>');
  add('<polyline points="31.2,-18 31.2,18 0,36 -31.2,18" fill="none" '
      'stroke="${look.dark}" stroke-width="1.6" stroke-linejoin="round" '
      'opacity=".35"/>');

  if (look.ring) {
    add('<polygon points="$_hexRing" fill="none" stroke="${look.light}" '
        'stroke-width="1" opacity=".8"/>');
  }
  if (look.rivets) {
    add('<g fill="${look.rivet}" stroke="${look.rivetStroke}" '
        'stroke-width=".6">');
    for (final (cx, cy) in _rivetCenters) {
      add('  <circle cx="${_n(cx)}" cy="${_n(cy)}" r="1.8"/>');
    }
    add('</g>');
  }

  // La barra: mango y manguito de punta a punta, discos y collarines.
  add('<rect x="-27.5" y="-3" width="55" height="6" rx="1" '
      'fill="${look.light}" stroke="${look.dark}" stroke-width=".7"/>');
  add('<path d="${_platesPath(_platesFor(rank))}" fill="${look.dark}" '
      'stroke="${look.light}" stroke-width=".7" stroke-linejoin="round"/>');
  add('<path d="M25.7 -4h1.8v8h-1.8z M-27.5 -4h1.8v8h-1.8z" '
      'fill="${look.light}" stroke="${look.dark}" stroke-width=".6"/>');
  add('<path d="M-3 -1.8v3.6 M0 -1.8v3.6 M3 -1.8v3.6" stroke="${look.dark}" '
      'stroke-width=".6" opacity=".55"/>');

  if (look.star) {
    add('<polygon transform="translate(0,-49)" points="0,-7 1.76,-2.43 '
        '6.66,-2.16 2.85,0.93 4.11,5.66 0,3 -4.11,5.66 -2.85,0.93 -6.66,-2.16 '
        '-1.76,-2.43" fill="#FFD34D" stroke="#6B4400" stroke-width=".8" '
        'stroke-linejoin="round"/>');
  }

  return _wrap(lines);
}

/// "Sin rango": hexágono punteado y una barra sin discos. Un solo color (negro):
/// se tiñe en runtime con un `ColorFilter`, así que el color de acá no se ve.
String _unranked() => _wrap([
      '  <polygon points="$_hexOuter" fill="none" stroke="#000" '
          'stroke-width="3" stroke-linejoin="round" stroke-dasharray="6 4"/>',
      '  <rect x="-27.5" y="-3" width="55" height="6" rx="1" fill="#000"/>',
      '  <path d="M25.7 -4h1.8v8h-1.8z M-27.5 -4h1.8v8h-1.8z" fill="#000"/>',
    ]);

String _wrap(List<String> lines) => [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-60 -60 120 120" '
          'width="120" height="120">',
      '  $_banner',
      ...lines,
      '</svg>',
      '',
    ].join('\n');

/// Todos los SVG, por nombre de archivo (`bronze.svg` … `olympian.svg` y
/// `unranked.svg`). Separado de [main] para que el test de sincronismo compare
/// los archivos commiteados contra exactamente lo que genera esto.
Map<String, String> buildLiftRankBadgeSvgs() => {
      for (var rank = 1; rank <= kLiftRankBadgeCount; rank++)
        '${kLiftRankBadgeNames[rank - 1]}.svg': _badge(rank),
      'unranked.svg': _unranked(),
    };

void main() {
  final dir = Directory(_outDir)..createSync(recursive: true);
  final svgs = buildLiftRankBadgeSvgs();
  for (final entry in svgs.entries) {
    File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
  }

  stdout.writeln('Generado en $_outDir/:');
  for (final entry in svgs.entries) {
    stdout.writeln('  ${entry.key}  (${entry.value.length} bytes)');
  }
}
