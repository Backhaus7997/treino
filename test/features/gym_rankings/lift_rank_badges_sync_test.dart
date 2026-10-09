// Guard de deriva entre el generador de insignias y los SVG commiteados.
//
// `assets/ranking_ranks/*.svg` los genera `tool/build_lift_rank_badges.dart`.
// Nada obliga a correr el generador: alguien retoca un SVG a mano, o cambia una
// paleta en el Dart y se olvida de regenerar, y las ocho insignias de la familia
// dejan de ser consistentes entre sí sin que nadie lo note.
//
// Mismo esquema que `test/legal/paginas_legales_sync_test.dart`: este test es el
// que avisa, en vez de un usuario.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gym_rankings/domain/lift_rank.dart';

import '../../../tool/build_lift_rank_badges.dart';

/// Los checkouts de Windows con `core.autocrlf` entregan CRLF; el generador
/// escribe LF. El contenido es el mismo.
String _lf(String s) => s.replaceAll('\r\n', '\n');

void main() {
  final generados = buildLiftRankBadgeSvgs();

  test('el generador produce un SVG por rango más unranked', () {
    expect(generados.length, LiftRank.values.length);
    for (final rank in LiftRank.values) {
      expect(generados.containsKey('${rank.assetName}.svg'), isTrue,
          reason: 'el generador no produce ${rank.assetName}.svg');
    }
  });

  test('los nombres del generador son los del enum, en el mismo orden', () {
    expect(
      kLiftRankBadgeNames,
      LiftRank.values.skip(1).map((r) => r.name).toList(),
    );
    expect(kLiftRankBadgeCount, LiftRank.values.length - 1);
  });

  group('los SVG commiteados no derivaron del generador', () {
    for (final entry in generados.entries) {
      test(entry.key, () {
        final file = File('assets/ranking_ranks/${entry.key}');
        expect(file.existsSync(), isTrue,
            reason: '${file.path} no existe — '
                'corré `dart run tool/build_lift_rank_badges.dart`');
        expect(
          _lf(file.readAsStringSync()),
          entry.value,
          reason: '${file.path} no coincide con lo que genera '
              '`tool/build_lift_rank_badges.dart`. No se edita a mano: '
              'tocá el generador y corré `dart run tool/build_lift_rank_badges.dart`',
        );
      });
    }

    test('no sobra ningún SVG que el generador no produzca', () {
      final enDisco = Directory('assets/ranking_ranks')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(enDisco, generados.keys.toSet());
    });
  });

  group('cada insignia es un SVG bien formado y de un tamaño razonable', () {
    for (final entry in generados.entries) {
      test(entry.key, () {
        final svg = entry.value;
        expect(svg, startsWith('<svg '));
        expect(svg.trimRight(), endsWith('</svg>'));
        expect(svg, contains('viewBox="-60 -60 120 120"'));
        // Ocho de nueve pesan menos de 3,5 KB. Si una pasa de 8 KB, algo se
        // desbocó (un bucle, un número sin redondear).
        expect(svg.length, lessThan(8 * 1024));
      });
    }
  });
}
