// La insignia de rango: dibuja el SVG que corresponde, tiene el tamaño pedido,
// no se tiñe (salvo "sin rango") y no expone semántica propia.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gym_rankings/domain/lift_rank.dart';
import 'package:treino/features/gym_rankings/presentation/widgets/lift_rank_badge.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

/// `SvgPicture.asset` carga el archivo de forma asíncrona con I/O real: el
/// reloj falso de `testWidgets` no lo adelanta.
Future<void> _settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

String _assetOf(WidgetTester tester) {
  final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
  return (svg.bytesLoader as SvgAssetLoader).assetName;
}

void main() {
  group('LiftRankBadge', () {
    testWidgets('dibuja el SVG del rango pedido', (tester) async {
      await tester.pumpWidget(
        _host(const LiftRankBadge(rank: LiftRank.gold)),
      );
      await _settle(tester);

      expect(_assetOf(tester), 'assets/ranking_ranks/gold.svg');
    });

    testWidgets('cada rango apunta a su propio archivo', (tester) async {
      for (final rank in LiftRank.values) {
        await tester.pumpWidget(_host(LiftRankBadge(rank: rank)));
        await _settle(tester);
        expect(_assetOf(tester), rank.assetPath, reason: rank.name);
      }
    });

    testWidgets('respeta el tamaño pedido', (tester) async {
      await tester.pumpWidget(
        _host(
          const LiftRankBadge(
            rank: LiftRank.titan,
            size: LiftRankBadge.featuredSize,
          ),
        ),
      );
      await _settle(tester);

      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, LiftRankBadge.featuredSize);
      expect(svg.height, LiftRankBadge.featuredSize);
    });

    testWidgets('los rangos con material fijo NO se tiñen', (tester) async {
      await tester.pumpWidget(
        _host(const LiftRankBadge(rank: LiftRank.olympian)),
      );
      await _settle(tester);

      // Un `srcIn` los dejaría en una silueta plana de un solo color.
      expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          isNull);
    });

    testWidgets('"sin rango" sí toma el color apagado del tema',
        (tester) async {
      await tester.pumpWidget(
        _host(const LiftRankBadge(rank: LiftRank.none)),
      );
      await _settle(tester);

      expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          isNotNull);
    });

    testWidgets('es decorativa: no expone semántica propia', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const LiftRankBadge(rank: LiftRank.diamond)),
      );
      await _settle(tester);

      // El rango lo dice el texto de al lado (la franja) o la etiqueta de la
      // fila: la insignia sola no debe anunciar nada.
      final semantics = tester.getSemantics(find.byType(LiftRankBadge));
      expect(semantics.label, isEmpty);
      handle.dispose();
    });
  });
}
