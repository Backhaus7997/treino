// Tests de la pantalla de tendencia de bienestar (#643 slice 3).
//
// Dos cosas se testean acá y el resto es chrome:
//   1. LOS TRES ESTADOS DE DATO se distinguen — sin registros, con uno solo
//      (un dato no es una curva) y con serie. Son tres mensajes distintos
//      porque son tres situaciones distintas para el usuario.
//   2. REGISTRAR, NO INTERPRETAR — el límite duro del issue. La pantalla
//      cuenta y muestra; no diagnostica, no recomienda, no califica un número
//      como bueno ni malo, y no lleva puntaje ni racha (AGENTS.md regla 4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/application/wellbeing_trend_providers.dart';
import 'package:treino/features/insights/domain/wellbeing_trend.dart';
import 'package:treino/features/insights/presentation/wellbeing_trend_screen.dart';
import 'package:treino/features/insights/presentation/widgets/wellbeing_trend_chart.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'u1';

WellbeingTrendPoint _p(String date, double level, {bool pain = false}) =>
    (date: date, feelingLevel: level, hadPain: pain);

Widget _host(WellbeingTrend trend) {
  return ProviderScope(
    overrides: [
      wellbeingTrendProvider.overrideWith((ref, key) => Future.value(trend)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(body: WellbeingTrendScreen(uid: _uid)),
    ),
  );
}

void main() {
  testWidgets('sin registros muestra el empty state y ningún chart',
      (tester) async {
    await tester.pumpWidget(_host(emptyWellbeingTrend));
    await tester.pumpAndSettle();

    expect(find.text('CÓMO ME SENTÍ'), findsOneWidget);
    expect(
      find.textContaining('Todavía no registraste cómo te sentís'),
      findsOneWidget,
    );
    expect(find.byType(WellbeingTrendChart), findsNothing);
  });

  testWidgets('con UN solo día el mensaje es otro: un dato no es una curva',
      (tester) async {
    await tester.pumpWidget(_host((
      points: [_p('2026-05-03', 3)],
      recordCount: 1,
      painCount: 0,
      previousRecordCount: 0,
      previousPainCount: 0,
      painByArea: const [],
    )));
    await tester.pumpAndSettle();

    expect(
      find.text('Con un solo registro todavía no hay tendencia que mostrar.'),
      findsOneWidget,
    );
    expect(find.byType(WellbeingTrendChart), findsNothing);
    // Pero el conteo sí se muestra: hay dato, aunque no haya curva.
    expect(find.textContaining('0 de 1 registros con dolor'), findsOneWidget);
  });

  testWidgets('con dos o más días dibuja el chart', (tester) async {
    await tester.pumpWidget(_host((
      points: [_p('2026-05-03', 1, pain: true), _p('2026-05-10', 3)],
      recordCount: 2,
      painCount: 1,
      previousRecordCount: 0,
      previousPainCount: 0,
      painByArea: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.byType(WellbeingTrendChart), findsOneWidget);
  });

  testWidgets(
      'el conteo del período anterior aparece junto al actual, sin '
      'calificar la diferencia', (tester) async {
    await tester.pumpWidget(_host((
      points: [_p('2026-05-03', 1, pain: true), _p('2026-05-10', 3)],
      recordCount: 8,
      painCount: 2,
      previousRecordCount: 10,
      previousPainCount: 7,
      painByArea: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.text('2 de 8 registros con dolor'), findsOneWidget);
    expect(find.text('Período anterior: 7 de 10'), findsOneWidget);
  });

  testWidgets('sin período anterior no se inventa una comparación',
      (tester) async {
    await tester.pumpWidget(_host((
      points: [_p('2026-05-03', 1), _p('2026-05-10', 3)],
      recordCount: 2,
      painCount: 0,
      previousRecordCount: 0,
      previousPainCount: 0,
      painByArea: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Período anterior'), findsNothing);
  });

  testWidgets('las zonas usan el vocabulario de MuscleGroup, no uno propio',
      (tester) async {
    await tester.pumpWidget(_host((
      points: [
        _p('2026-05-03', 1, pain: true),
        _p('2026-05-10', 2, pain: true)
      ],
      recordCount: 2,
      painCount: 2,
      previousRecordCount: 0,
      previousPainCount: 0,
      painByArea: [
        (area: MuscleGroup.espalda, count: 2),
        (area: MuscleGroup.cuadriceps, count: 1),
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('ZONAS REGISTRADAS'), findsOneWidget);
    expect(find.text(MuscleGroup.espalda.label), findsOneWidget);
    expect(find.text(MuscleGroup.cuadriceps.label), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  // ── Registrar, no interpretar ────────────────────────────────────────────

  testWidgets(
      'con dolor aparece el aviso neutro, y ningún consejo ni diagnóstico',
      (tester) async {
    await tester.pumpWidget(_host((
      points: [
        _p('2026-05-03', 0, pain: true),
        _p('2026-05-10', 1, pain: true)
      ],
      recordCount: 6,
      painCount: 5,
      previousRecordCount: 6,
      previousPainCount: 1,
      painByArea: [(area: MuscleGroup.espalda, count: 5)],
    )));
    await tester.pumpAndSettle();

    expect(
      find.text('Si el dolor persiste, consultá a un profesional de la salud.'),
      findsOneWidget,
    );

    // El escenario de arriba es el más tentador para que alguien agregue una
    // lectura: el dolor subió fuerte contra el período anterior. Si aparece
    // copy que interprete, juzgue o premie, este test lo frena.
    for (final forbidden in [
      'Te recomendamos',
      'Deberías',
      'Es normal',
      'No entrenes',
      'Descansá',
      'Mejoraste',
      'Empeoraste',
      'Cuidado',
      'Alerta',
      'racha',
      'Racha',
      'puntos',
      'Puntos',
      'Nivel',
    ]) {
      expect(find.textContaining(forbidden), findsNothing,
          reason: 'la pantalla no puede decir "$forbidden"');
    }
  });

  testWidgets('sin dolor el aviso médico no aparece', (tester) async {
    await tester.pumpWidget(_host((
      points: [_p('2026-05-03', 3), _p('2026-05-10', 4)],
      recordCount: 2,
      painCount: 0,
      previousRecordCount: 0,
      previousPainCount: 0,
      painByArea: const [],
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('consultá a un profesional'), findsNothing);
  });

  testWidgets('el error ofrece reintentar en vez de tapar la pantalla',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wellbeingTrendProvider.overrideWith(
            (ref, key) => Future.error(Exception('boom')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: WellbeingTrendScreen(uid: _uid)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tu registro. Probá de nuevo.'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsWidgets);
  });
}
