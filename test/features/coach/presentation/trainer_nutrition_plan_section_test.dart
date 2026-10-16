import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_nutrition_plan_section.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerId = 't1';
const _athleteId = 'a1';

NutritionPlan _plan({String title = 'Plan de fuerza'}) => NutritionPlan(
      id: '${_trainerId}_$_athleteId',
      trainerId: _trainerId,
      athleteId: _athleteId,
      title: title,
      meals: const [
        Meal(id: 'm1', name: 'Desayuno', groups: []),
        Meal(id: 'm2', name: 'Almuerzo', groups: []),
        Meal(id: 'm3', name: 'Cena', groups: []),
      ],
      updatedAt: DateTime(2026, 10, 16, 12),
    );

Future<void> _pump(WidgetTester tester, Stream<NutritionPlan?> plan) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/$_athleteId',
    routes: [
      GoRoute(
        path: '/coach/athlete/:athleteId',
        builder: (_, __) => const Scaffold(
          body: TrainerNutritionPlanSection(
            athleteId: _athleteId,
            trainerUid: _trainerId,
          ),
        ),
      ),
      GoRoute(
        path: '/coach/athlete/:athleteId/nutricion',
        builder: (_, state) => Scaffold(
          body: Text('editor:${state.pathParameters['athleteId']}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionPlanProvider((trainerId: _trainerId, athleteId: _athleteId))
            .overrideWith((ref) => plan),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  testWidgets('sin plan: lo dice, ofrece + Cargar y abre el editor',
      (tester) async {
    await _pump(tester, Stream.value(null));
    await tester.pumpAndSettle();

    expect(find.text('PLAN NUTRICIONAL'), findsOneWidget);
    expect(
      find.text('Todavía no le cargaste un plan nutricional.'),
      findsOneWidget,
    );

    await tester.tap(find.text('+ Cargar'));
    await tester.pumpAndSettle();
    expect(find.text('editor:$_athleteId'), findsOneWidget);
  });

  testWidgets('con plan: título, cantidad de comidas y fecha; ofrece Editar',
      (tester) async {
    await _pump(tester, Stream.value(_plan()));
    await tester.pumpAndSettle();

    expect(find.text('Plan de fuerza'), findsOneWidget);
    expect(
        find.textContaining('3 comidas · actualizado el 16 '), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('+ Cargar'), findsNothing);

    // La card entera también abre el editor, no sólo la acción del header.
    await tester.tap(find.text('Plan de fuerza'));
    await tester.pumpAndSettle();
    expect(find.text('editor:$_athleteId'), findsOneWidget);
  });

  testWidgets('el título es opcional: sin título dice «Plan nutricional»',
      (tester) async {
    await _pump(tester, Stream.value(_plan(title: '  ')));
    await tester.pumpAndSettle();

    expect(find.text('Plan nutricional'), findsOneWidget);
  });

  // «+ Cargar» mientras carga le diría al PF que su alumno no tiene plan,
  // justo antes de que aparezca el que tiene.
  testWidgets('mientras carga no ofrece ninguna acción', (tester) async {
    final pending = StreamController<NutritionPlan?>();
    addTearDown(pending.close);
    await _pump(tester, pending.stream);
    await tester.pump();

    expect(find.text('Cargando…'), findsOneWidget);
    expect(find.text('+ Cargar'), findsNothing);
    expect(find.text('Editar'), findsNothing);
  });

  testWidgets('si la lectura falla se degrada sólo la sección', (tester) async {
    await _pump(tester, Stream.error(Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar el plan nutricional.'), findsOneWidget);
    expect(find.text('+ Cargar'), findsNothing);
  });
}
