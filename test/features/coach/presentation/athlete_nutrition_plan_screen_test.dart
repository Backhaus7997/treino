import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/presentation/athlete_nutrition_plan_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';

NutritionPlan _plan() => NutritionPlan(
      id: '${_trainerId}_$_athleteId',
      trainerId: _trainerId,
      athleteId: _athleteId,
      title: 'Plan de fuerza',
      meals: const [
        Meal(
          id: 'breakfast',
          name: 'Desayuno',
          time: '08:00',
          groups: [
            FoodGroup(
              id: 'carbs',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [
                FoodOption(
                  id: 'toast',
                  name: 'Tostadas integrales',
                  quantity: '2',
                  unit: 'unidades',
                  notes: 'Podés sumar semillas.',
                ),
                FoodOption(id: 'oats', name: 'Avena'),
              ],
            ),
            FoodGroup(
              id: 'protein',
              name: 'Proteínas',
              selectionMode: SelectionMode.all,
              options: [
                FoodOption(id: 'eggs', name: 'Huevos'),
              ],
            ),
          ],
        ),
      ],
      updatedAt: DateTime.utc(2026, 9, 1),
    );

NutritionPlan _planConGrupoVacio() => NutritionPlan(
      id: '${_trainerId}_$_athleteId',
      trainerId: _trainerId,
      athleteId: _athleteId,
      title: 'Plan a medio cargar',
      meals: const [
        Meal(
          id: 'breakfast',
          name: 'Desayuno',
          time: '08:00',
          groups: [
            FoodGroup(
              id: 'protein',
              name: 'Proteínas',
              selectionMode: SelectionMode.chooseOne,
              options: [],
            ),
          ],
        ),
      ],
      updatedAt: DateTime.utc(2026, 9, 1),
    );

Widget _wrap(NutritionPlan? plan) => ProviderScope(
      overrides: [
        nutritionPlanProvider(
          (trainerId: _trainerId, athleteId: _athleteId),
        ).overrideWith((ref) => Stream.value(plan)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: AthleteNutritionPlanScreen(
            trainerId: _trainerId,
            athleteId: _athleteId,
          ),
        ),
      ),
    );

void main() {
  testWidgets('renderiza comidas, grupos, opciones y modos de selección',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(_plan()));
    await tester.pumpAndSettle();

    expect(find.text('PLAN DE FUERZA'), findsOneWidget);
    expect(find.text('DESAYUNO'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('HIDRATOS'), findsOneWidget);
    expect(find.text('PROTEÍNAS'), findsOneWidget);
    expect(find.text('Elegí una'), findsOneWidget);
    expect(find.text('Va todo'), findsOneWidget);
    expect(find.text('Tostadas integrales'), findsOneWidget);
    expect(find.text('2 unidades'), findsOneWidget);
    expect(find.text('Podés sumar semillas.'), findsOneWidget);
    expect(find.text('Avena'), findsOneWidget);
    expect(find.text('Huevos'), findsOneWidget);
  });

  testWidgets('plan null muestra el vacío y no el error', (tester) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pumpAndSettle();

    expect(
      find.text('Tu PF todavía no cargó tu plan nutricional.'),
      findsOneWidget,
    );
    expect(find.text('No pudimos cargar tu plan nutricional.'), findsNothing);
  });
  // Un grupo sin opciones quedaba con el título, el hint, y NADA debajo. Eso
  // no se lee como información: se lee como un control esperando que elijas
  // algo — y encima el hint estaba pintado con el color de las acciones.
  //
  // Reportado mirando la pantalla real: «me sale como si pudiera elegir algo
  // debajo de cada título».
  testWidgets('un grupo sin opciones lo dice, no queda en silencio',
      (tester) async {
    await tester.pumpWidget(_wrap(_planConGrupoVacio()));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    expect(find.text(l10n.athleteNutritionEmptyGroup), findsOneWidget);
    // El hint de la regla sigue estando: dice CÓMO se come ese grupo, y eso
    // no deja de ser cierto porque todavía no haya opciones.
    expect(find.text(l10n.athleteNutritionChooseOneHint), findsOneWidget);
  });

  // Control del anterior: con opciones cargadas NO aparece el cartel de vacío.
  // Sin esto, un mensaje que se mostrara siempre pasaría el test de arriba.
  testWidgets('con opciones cargadas no aparece el cartel de vacío',
      (tester) async {
    await tester.pumpWidget(_wrap(_plan()));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    expect(find.text(l10n.athleteNutritionEmptyGroup), findsNothing);
    expect(find.text('Avena'), findsOneWidget);
  });
}
