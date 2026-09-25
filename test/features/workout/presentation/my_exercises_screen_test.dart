// Selección múltiple + borrado en lote de «Mis ejercicios».
//
// Borrar de a uno obligaba a entrar al editor, borrar, volver y repetir: cuatro
// toques por ejercicio. Estos tests fijan el flujo que lo baja a uno por
// ejercicio más una confirmación para todo el lote.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/presentation/my_exercises_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockRepo extends Mock implements CustomExerciseRepository {}

const _kUid = 'trainer-1';

CustomExercise _ex(String id, String name) => CustomExercise(
      id: id,
      ownerId: _kUid,
      name: name,
      muscleGroup: 'chest',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserProfile _profile(UserRole role) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    uid: _kUid,
    email: 'a@b.com',
    displayName: null,
    role: role,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<CustomExercise> items,
  CustomExerciseRepository? repo,
  UserRole role = UserRole.trainer,
  AsyncValue<CustomExerciseQuota>? quota,
  UserRepository? userRepo,
}) async {
  final router = GoRouter(
    initialLocation: '/profile/my-exercises',
    routes: [
      GoRoute(
        path: '/profile/my-exercises',
        builder: (_, __) => const Scaffold(body: MyExercisesScreen()),
      ),
      GoRoute(
        path: '/profile/my-exercises/new',
        builder: (_, __) => const Scaffold(body: Text('nuevo')),
      ),
      GoRoute(
        path: '/profile/my-exercises/:id',
        builder: (_, s) =>
            Scaffold(body: Text('editar ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kUid),
        if (repo != null)
          customExerciseRepositoryProvider.overrideWithValue(repo),
        customExercisesForTrainerStreamProvider(_kUid)
            .overrideWith((ref) => Stream.value(items)),
        userProfileProvider.overrideWith((ref) => Stream.value(_profile(role))),
        customExerciseQuotaProvider.overrideWithValue(
          quota ?? AsyncValue.data((limit: null, count: items.length)),
        ),
        userRepositoryProvider.overrideWithValue(userRepo ?? _MockUserRepo()),
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
}

void main() {
  setUpAll(() => registerFallbackValue(_ex('x', 'x')));

  testWidgets('sin modo selección: tap navega al editor', (tester) async {
    await _pump(tester, items: [_ex('a', 'Press banca')]);

    expect(find.text('MIS EJERCICIOS'), findsOneWidget);
    await tester.tap(find.text('Press banca'));
    await tester.pumpAndSettle();

    expect(find.text('editar a'), findsOneWidget);
  });

  testWidgets('lista vacía → no ofrece SELECCIONAR', (tester) async {
    await _pump(tester, items: const []);

    // Un botón de seleccionar sobre una lista vacía no puede hacer nada.
    expect(find.text('SELECCIONAR'), findsNothing);
  });

  testWidgets('SELECCIONAR entra al modo y el tap deja de navegar',
      (tester) async {
    await _pump(tester, items: [_ex('a', 'Press banca'), _ex('b', 'Remo')]);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();

    expect(find.text('0 SELECCIONADOS'), findsOneWidget);

    await tester.tap(find.text('Press banca'));
    await tester.pumpAndSettle();

    // Sigue en la lista: el tap alterna, no navega. Navegar sacaría al usuario
    // de la pantalla en medio de armar un lote.
    expect(find.text('editar a'), findsNothing);
    expect(find.text('1 SELECCIONADOS'), findsOneWidget);
  });

  testWidgets('long-press entra al modo con ese ejercicio ya tildado',
      (tester) async {
    await _pump(tester, items: [_ex('a', 'Press banca'), _ex('b', 'Remo')]);

    await tester.longPress(find.text('Press banca'));
    await tester.pumpAndSettle();

    expect(find.text('1 SELECCIONADOS'), findsOneWidget);
  });

  testWidgets('TODOS marca todo y vuelve a NINGUNO', (tester) async {
    await _pump(tester, items: [_ex('a', 'A'), _ex('b', 'B'), _ex('c', 'C')]);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TODOS'));
    await tester.pumpAndSettle();

    expect(find.text('3 SELECCIONADOS'), findsOneWidget);

    // El mismo botón desmarca: un "seleccionar todos" que no sabe volver atrás
    // obliga a destildar de a uno.
    expect(find.text('NINGUNO'), findsOneWidget);
    await tester.tap(find.text('NINGUNO'));
    await tester.pumpAndSettle();

    expect(find.text('0 SELECCIONADOS'), findsOneWidget);
  });

  testWidgets('con cero seleccionados el botón de borrar está deshabilitado',
      (tester) async {
    await _pump(tester, items: [_ex('a', 'A')]);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();

    final btn = tester.widget<ElevatedButton>(
      find.byKey(const Key('my_exercises_delete_selected')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('borrar en lote: confirma y llama delete por cada uno',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.delete(
        trainerId: any(named: 'trainerId'),
        id: any(named: 'id'))).thenAnswer((_) async {});

    await _pump(
      tester,
      items: [_ex('a', 'A'), _ex('b', 'B'), _ex('c', 'C')],
      repo: repo,
    );

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();

    expect(find.text('2 SELECCIONADOS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my_exercises_delete_selected')));
    await tester.pumpAndSettle();

    // Confirmación destructiva antes de tocar nada.
    expect(find.text('Borrar 2 ejercicios'), findsOneWidget);
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    verify(() => repo.delete(trainerId: _kUid, id: 'a')).called(1);
    verify(() => repo.delete(trainerId: _kUid, id: 'c')).called(1);
    verifyNever(() => repo.delete(trainerId: _kUid, id: 'b'));
  });

  testWidgets('cancelar la confirmación no borra nada', (tester) async {
    final repo = _MockRepo();

    await _pump(tester, items: [_ex('a', 'A')], repo: repo);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my_exercises_delete_selected')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() =>
        repo.delete(trainerId: any(named: 'trainerId'), id: any(named: 'id')));
    // Sigue en modo selección con lo elegido: cancelar la confirmación no es
    // cancelar la selección.
    expect(find.text('1 SELECCIONADOS'), findsOneWidget);
  });

  testWidgets('si alguno falla, queda seleccionado y el mensaje lo dice',
      (tester) async {
    final repo = _MockRepo();
    when(() => repo.delete(trainerId: _kUid, id: 'a')).thenAnswer((_) async {});
    when(() => repo.delete(trainerId: _kUid, id: 'b'))
        .thenAnswer((_) async => throw Exception('denied'));

    await _pump(tester, items: [_ex('a', 'A'), _ex('b', 'B')], repo: repo);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TODOS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my_exercises_delete_selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    // Un `Future.wait` que explota en el primero dejaría el resto en un estado
    // que nadie sabe cuál es. Acá el mensaje puede decir la verdad, y el que
    // falló queda tildado para reintentar sin volver a buscarlo.
    expect(find.textContaining('No pudimos borrar 1 de 2'), findsOneWidget);
    expect(find.text('1 SELECCIONADOS'), findsOneWidget);
  });

  testWidgets('el back del sistema sale del modo, no de la pantalla',
      (tester) async {
    await _pump(tester, items: [_ex('a', 'A')]);

    await tester.tap(find.text('SELECCIONAR'));
    await tester.pumpAndSettle();
    expect(find.text('0 SELECCIONADOS'), findsOneWidget);

    // Salirse de la pantalla entera por querer cancelar una selección es la
    // clase de sorpresa que hace desconfiar del back.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('MIS EJERCICIOS'), findsOneWidget);
    expect(find.text('0 SELECCIONADOS'), findsNothing);
  });

  // ── Tope de ejercicios propios (docs/limite-ejercicios-pf.md PR3) ────────

  group('contador de ejercicios propios', () {
    testWidgets('PF con límite numérico ⇒ lo muestra', (tester) async {
      await _pump(
        tester,
        items: [_ex('a', 'A'), _ex('b', 'B')],
        quota: const AsyncValue.data((limit: 60, count: 2)),
      );

      expect(find.text('2 de 60 ejercicios propios'), findsOneWidget);
    });

    testWidgets('límite null (Plan 3 / interruptor apagado) ⇒ lo oculta',
        (tester) async {
      await _pump(
        tester,
        items: [_ex('a', 'A')],
        quota: const AsyncValue.data((limit: null, count: 1)),
      );

      expect(find.textContaining('ejercicios propios'), findsNothing);
    });

    testWidgets('alumno ⇒ nunca lo muestra, aunque la cuota traiga un límite',
        (tester) async {
      await _pump(
        tester,
        items: [_ex('a', 'A')],
        role: UserRole.athlete,
        // Esto no puede pasar en producción (planLimits.customExercises sólo
        // lo escribe la CF para role == trainer), pero el widget igual tiene
        // que cortar por rol y no confiar ciegamente en el dato.
        quota: const AsyncValue.data((limit: 60, count: 1)),
      );

      expect(find.textContaining('ejercicios propios'), findsNothing);
    });
  });

  group('CTA "+ NUEVO EJERCICIO" — el embudo único', () {
    testWidgets('PF bajo el tope ⇒ navega al editor', (tester) async {
      await _pump(
        tester,
        items: [_ex('a', 'A')],
        quota: const AsyncValue.data((limit: 60, count: 1)),
      );

      await tester.tap(find.text('+ NUEVO EJERCICIO'));
      await tester.pumpAndSettle();

      expect(find.text('nuevo'), findsOneWidget);
    });

    testWidgets('PF en el tope ⇒ NO navega y muestra el aviso de sólo-estado',
        (tester) async {
      final userRepo = _MockUserRepo();
      when(() => userRepo.registrarTopeDelPlanPf(any(), any()))
          .thenAnswer((_) async {});

      await _pump(
        tester,
        items: [_ex('a', 'A')],
        quota: const AsyncValue.data((limit: 1, count: 1)),
        userRepo: userRepo,
      );

      await tester.tap(find.text('+ NUEVO EJERCICIO'));
      await tester.pumpAndSettle();

      expect(find.text('nuevo'), findsNothing);
      expect(
        find.text('Llegaste a los 1 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsOneWidget,
      );
      // Sin botón de acción: sólo el dismiss de "sólo-estado".
      expect(find.byKey(const Key('trainer_limit_dismiss')), findsOneWidget);
    });

    testWidgets('alumno ⇒ navega siempre, aunque la cuota diga tope',
        (tester) async {
      await _pump(
        tester,
        items: [_ex('a', 'A')],
        role: UserRole.athlete,
        quota: const AsyncValue.data((limit: 1, count: 1)),
      );

      await tester.tap(find.text('+ NUEVO EJERCICIO'));
      await tester.pumpAndSettle();

      expect(find.text('nuevo'), findsOneWidget);
    });
  });
}
