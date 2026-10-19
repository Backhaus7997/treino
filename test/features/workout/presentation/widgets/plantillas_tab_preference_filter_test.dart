// Estado vacío del filtro duro de días/minutos de EXPLORAR (#1561): mensaje
// con plural + CTA "Ver todas" que levanta el filtro (estado en el provider).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/template_preferences_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';
import 'package:treino/l10n/app_l10n.dart';

Routine _r(String id, int days, {int? minutes}) => Routine(
      id: id,
      name: 'Plantilla $id',
      level: ExperienceLevel.beginner,
      estimatedMinutesPerDay: minutes,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(dayNumber: i + 1, name: 'Día ${i + 1}', slots: const []),
      ],
    );

final _catalogo = [_r('a', 3, minutes: 60), _r('b', 5, minutes: 60)];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  TemplatePreferences prefs, {
  List<Routine>? catalogo,
  ExperienceLevel? level,
  String query = '',
}) async {
  final container = ProviderContainer(overrides: [
    currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
    routinesProvider.overrideWith((ref) async => catalogo ?? _catalogo),
    athleteTemplatePreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  container.read(routinesLevelFilterProvider.notifier).state = level;
  container.read(templatesSearchQueryProvider.notifier).state = query;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: SizedBox(height: 1200, child: PlantillasTab()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void main() {
  testWidgets('con 3 días sólo se ven las de 3 días', (tester) async {
    await _pump(tester, const TemplatePreferences(daysPerWeek: 3));
    expect(find.byType(RoutineCard), findsOneWidget);
    expect(find.text('PLANTILLA A'), findsOneWidget);
    expect(find.text('PLANTILLA B'), findsNothing);
  });

  testWidgets('vacío por días: mensaje con plural y CTA que levanta el filtro',
      (tester) async {
    final container =
        await _pump(tester, const TemplatePreferences(daysPerWeek: 6));

    expect(find.byType(RoutineCard), findsNothing);
    expect(find.text('No hay plantillas de 6 días'), findsOneWidget);
    final cta = find.text('Ver todas');
    expect(cta, findsOneWidget);

    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(container.read(templatesPreferenceFilterLiftedProvider), isTrue);
    expect(find.byType(RoutineCard), findsNWidgets(2));
    expect(find.text('No hay plantillas de 6 días'), findsNothing);
  });

  testWidgets('singular: 1 día', (tester) async {
    // Una sola rutina de 2 días ⇒ pedir 1 día no existe en el cuestionario,
    // pero el plural tiene que leerse bien igual.
    await _pump(tester, const TemplatePreferences(daysPerWeek: 1));
    expect(find.text('No hay plantillas de 1 día'), findsOneWidget);
  });

  testWidgets('vacío sólo por minutos: mensaje de minutos', (tester) async {
    await _pump(tester, const TemplatePreferences(minutesPerSession: 30));
    expect(find.text('No hay plantillas de unos 30 min'), findsOneWidget);
    expect(find.text('Ver todas'), findsOneWidget);
  });

  testWidgets('sin filtro duro (sólo objetivo) no hay estado vacío ni CTA',
      (tester) async {
    await _pump(
      tester,
      const TemplatePreferences(priorityMuscleGroups: ['back']),
    );
    expect(find.byType(RoutineCard), findsNWidgets(2));
    expect(find.text('Ver todas'), findsNothing);
  });

  group('el vacío culpa a lo que lo causó', () {
    testWidgets('vacío por NIVEL con filtro duro: mensaje de nivel, sin CTA',
        (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(daysPerWeek: 3),
        level: ExperienceLevel.advanced,
      );
      expect(find.text('No hay rutinas para este nivel.'), findsOneWidget);
      expect(find.text('No hay plantillas de 3 días'), findsNothing);
      expect(find.text('Ver todas'), findsNothing,
          reason: 'levantar días/minutos no sacaría a la grilla del vacío');
    });

    testWidgets('vacío por TEXTO con filtro duro: mensaje de búsqueda, sin CTA',
        (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(daysPerWeek: 3),
        query: 'zzzz',
      );
      expect(find.textContaining('zzzz'), findsWidgets);
      expect(find.text('No hay plantillas de 3 días'), findsNothing);
      expect(find.text('Ver todas'), findsNothing);
    });

    testWidgets('vacío por DÍAS aunque también haya minutos que sí encajan',
        (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(daysPerWeek: 6, minutesPerSession: 60),
      );
      expect(find.text('No hay plantillas de 6 días'), findsOneWidget);
      expect(find.text('Ver todas'), findsOneWidget);
    });

    testWidgets('vacío por MINUTOS aunque también haya días que sí encajan',
        (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(daysPerWeek: 3, minutesPerSession: 30),
      );
      expect(find.text('No hay plantillas de unos 30 min'), findsOneWidget);
      expect(find.text('No hay plantillas de 3 días'), findsNothing);
      expect(find.text('Ver todas'), findsOneWidget);
    });

    testWidgets('días y minutos encajan por separado pero no juntos',
        (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(daysPerWeek: 3, minutesPerSession: 30),
        catalogo: [_r('a', 3, minutes: 60), _r('c', 5, minutes: 30)],
      );
      expect(
        find.text(
            'Ninguna plantilla encaja con tus días y tus minutos a la vez'),
        findsOneWidget,
      );
      expect(find.text('Ver todas'), findsOneWidget);
    });

    testWidgets('"75 o más" no dice "unos 75 min"', (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(minutesPerSession: 75),
        catalogo: [_r('a', 3, minutes: 30)],
      );
      expect(find.text('No hay plantillas de 75 min o más'), findsOneWidget);
      expect(find.text('No hay plantillas de unos 75 min'), findsNothing);
    });
  });

  group('la barra no dice "Filtrado" si nada filtra', () {
    testWidgets('con días: filtrado y ordenado', (tester) async {
      await _pump(tester, const TemplatePreferences(daysPerWeek: 3));
      expect(
          find.text('Filtrado y ordenado según lo que buscás'), findsOneWidget);
    });

    testWidgets('sólo objetivo/zonas: ordenado', (tester) async {
      await _pump(
        tester,
        const TemplatePreferences(priorityMuscleGroups: ['back']),
      );
      expect(find.text('Ordenado según lo que buscás'), findsOneWidget);
      expect(find.textContaining('Filtrado'), findsNothing);
    });

    testWidgets('después de "Ver todas": ordenado', (tester) async {
      await _pump(tester, const TemplatePreferences(daysPerWeek: 6));
      await tester.tap(find.text('Ver todas'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Ordenado según lo que buscás'), findsOneWidget);
      expect(find.textContaining('Filtrado'), findsNothing);
    });
  });
}
