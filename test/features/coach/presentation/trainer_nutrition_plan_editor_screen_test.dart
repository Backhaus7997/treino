import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/presentation/trainer_nutrition_plan_editor_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _trainerId = 't1';
const _athleteId = 'a1';
const _docId = '${_trainerId}_$_athleteId';

NutritionPlan _plan({List<Meal>? meals, String title = 'Plan de fuerza'}) =>
    NutritionPlan(
      id: _docId,
      trainerId: _trainerId,
      athleteId: _athleteId,
      title: title,
      meals: meals ??
          const [
            Meal(
              id: 'meal-1',
              name: 'Desayuno',
              time: '08:00',
              groups: [
                FoodGroup(
                  id: 'group-1',
                  name: 'Hidratos',
                  selectionMode: SelectionMode.chooseOne,
                  options: [
                    FoodOption(
                      id: 'opt-1',
                      name: 'Tostadas integrales',
                      quantity: '2',
                      unit: 'unidades',
                      notes: 'Podés sumar semillas.',
                    ),
                  ],
                ),
              ],
            ),
          ],
      updatedAt: DateTime.utc(2026, 9, 1),
    );

Future<FakeFirebaseFirestore> _firestoreWith(NutritionPlan? plan) async {
  final db = FakeFirebaseFirestore();
  if (plan != null) {
    await db.collection('nutrition_plans').doc(_docId).set(plan.toJson());
  }
  return db;
}

Future<NutritionPlan?> _saved(FakeFirebaseFirestore db) async {
  final snap = await db.collection('nutrition_plans').doc(_docId).get();
  final data = snap.data();
  return data == null ? null : NutritionPlan.fromJson(data);
}

/// Monta la ficha del alumno y empuja el editor encima, como en la app: así
/// `context.pop()` vuelve a algo y se puede ver a dónde llegó.
Future<void> _pumpEditor(
  WidgetTester tester, {
  required FakeFirebaseFirestore db,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/coach/athlete/$_athleteId',
    routes: [
      GoRoute(
        path: '/coach/athlete/:athleteId',
        builder: (_, __) => const Scaffold(body: Text('ficha')),
      ),
      GoRoute(
        path: '/coach/athlete/:athleteId/nutricion',
        builder: (_, state) => Scaffold(
          body: TrainerNutritionPlanEditorScreen(
            athleteId: state.pathParameters['athleteId']!,
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        currentUidProvider.overrideWithValue(_trainerId),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(
              uid: _athleteId,
              displayName: 'Martín García',
              displayNameLowercase: 'martín garcía',
            ),
          ),
        ),
        ...extra,
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
  await tester.pumpAndSettle();
  router.push('/coach/athlete/$_athleteId/nutricion');
  await tester.pumpAndSettle();
}

Finder _field(String text) => find.widgetWithText(TextFormField, text);

void main() {
  testWidgets('sin plan arranca de los presets y GUARDAR PLAN lo persiste',
      (tester) async {
    final db = await _firestoreWith(null);
    await _pumpEditor(tester, db: db);

    expect(find.text('PLAN NUTRICIONAL'), findsOneWidget);
    expect(find.text('Martín García'), findsOneWidget);
    expect(_field('Desayuno'), findsOneWidget);
    expect(_field('Cena'), findsOneWidget);

    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    final saved = await _saved(db);
    expect(saved, isNotNull);
    expect(saved!.trainerId, _trainerId);
    expect(saved.athleteId, _athleteId);
    expect(saved.meals.first.name, 'Desayuno');
    // Guardó y volvió a la ficha, avisando.
    expect(find.text('ficha'), findsOneWidget);
    expect(find.text('Plan nutricional guardado.'), findsOneWidget);
  });

  testWidgets('la opción se lee como fila y se edita en el sheet',
      (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    expect(find.text('Tostadas integrales'), findsOneWidget);
    expect(find.text('2 unidades'), findsOneWidget);
    expect(find.text('Podés sumar semillas.'), findsOneWidget);

    await tester.tap(find.text('Tostadas integrales'));
    await tester.pumpAndSettle();
    expect(find.text('EDITAR OPCIÓN'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Tostadas integrales'),
      'Pan de masa madre',
    );
    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();

    expect(find.text('Pan de masa madre'), findsOneWidget);
    expect(find.text('Tostadas integrales'), findsNothing);

    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    final option = (await _saved(db))!.meals.single.groups.single.options;
    expect(option.single.name, 'Pan de masa madre');
    expect(option.single.id, 'opt-1');
    expect(option.single.quantity, '2');
  });

  testWidgets('agregar opción: LISTO no anda sin alimento y el id no choca',
      (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    await tester.tap(find.text('+ Agregar opción'));
    await tester.pumpAndSettle();
    expect(find.text('NUEVA OPCIÓN'), findsOneWidget);

    final done = find.widgetWithText(ElevatedButton, 'LISTO');
    expect(tester.widget<ElevatedButton>(done).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ej: 5 discos de arroz'),
      'Avena',
    );
    await tester.pump();
    expect(tester.widget<ElevatedButton>(done).onPressed, isNotNull);
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(find.text('Avena'), findsOneWidget);

    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    final options = (await _saved(db))!.meals.single.groups.single.options;
    expect(options.map((o) => o.name), ['Tostadas integrales', 'Avena']);
    expect(options.map((o) => o.id).toSet().length, 2);
    // Los opcionales vacíos se guardan como null, no como ''.
    expect(options.last.quantity, isNull);
  });

  testWidgets('eliminar una opción desde el sheet la saca del plan',
      (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    await tester.tap(find.text('Tostadas integrales'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ELIMINAR OPCIÓN'));
    await tester.pumpAndSettle();

    expect(find.text('Tostadas integrales'), findsNothing);
    expect(find.text('Sin opciones todavía.'), findsOneWidget);
  });

  testWidgets('borrar una comida con opciones pide confirmación',
      (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    await tester.tap(find.byTooltip('Eliminar comida'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar «Desayuno»?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(_field('Desayuno'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar comida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(_field('Desayuno'), findsNothing);
  });

  testWidgets('salir con cambios sin guardar pide confirmación',
      (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    await tester.enterText(_field('Plan de fuerza'), 'Plan de definición');
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar cambios?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('ficha'), findsNothing);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(find.text('ficha'), findsOneWidget);
    expect((await _saved(db))!.title, 'Plan de fuerza');
  });

  testWidgets('sin cambios sale directo, sin diálogo', (tester) async {
    final db = await _firestoreWith(_plan());
    await _pumpEditor(tester, db: db);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('¿Descartar cambios?'), findsNothing);
    expect(find.text('ficha'), findsOneWidget);
  });

  // Arrancar de los presets cuando la lectura falla dejaba al PF a un toque
  // de pisar un plan que existe y no se pudo leer. Así lo hace el editor web.
  testWidgets('si la lectura falla NO ofrece guardar un plan de presets',
      (tester) async {
    final db = await _firestoreWith(null);
    await _pumpEditor(
      tester,
      db: db,
      extra: [
        nutritionPlanProvider.overrideWith(
          (ref, key) => Stream<NutritionPlan?>.error(Exception('offline')),
        ),
      ],
    );

    expect(find.text('No pudimos cargar el plan nutricional.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('GUARDAR PLAN'), findsNothing);
    expect(_field('Desayuno'), findsNothing);
  });

  // Un plan guardado por el editor web puede traer ids repetidos (su contador
  // arranca en 0 cada vez). Con ids como `Key`, eso tiraba abajo el build; y
  // sin normalizar, editar una comida editaba también su gemela.
  testWidgets('un plan con ids repetidos se edita comida por comida',
      (tester) async {
    final db = await _firestoreWith(_plan(meals: const [
      Meal(id: 'meal-1', name: 'Desayuno', groups: []),
      Meal(id: 'meal-1', name: 'Cena', groups: []),
    ]));
    await _pumpEditor(tester, db: db);

    expect(tester.takeException(), isNull);
    await tester.enterText(_field('Desayuno'), 'Desayuno liviano');
    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    final meals = (await _saved(db))!.meals;
    expect(meals.map((m) => m.name), ['Desayuno liviano', 'Cena']);
    expect(meals.map((m) => m.id).toSet().length, 2);
  });

  testWidgets('un plan sin ninguna comida con nombre no se guarda',
      (tester) async {
    final db = await _firestoreWith(_plan(meals: const [
      Meal(id: 'meal-1', name: 'Desayuno', groups: []),
    ]));
    await _pumpEditor(tester, db: db);

    await tester.enterText(_field('Desayuno'), '   ');
    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    expect(
      find.text('El plan está vacío. Agregá al menos una comida con nombre.'),
      findsOneWidget,
    );
    expect((await _saved(db))!.meals.single.name, 'Desayuno');
  });
}
