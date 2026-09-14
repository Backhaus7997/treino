import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/domain/parsed_plan.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _trainerUid = 'trainer-1';
const _atletas = <String, String>{
  'ath-1': 'Ana',
  'ath-2': 'Bruno',
  'ath-3': 'Carla',
};

UserProfile _trainer() => UserProfile(
      uid: _trainerUid,
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

TrainerLink _link(String athleteId) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: _trainerUid,
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

/// Plan SIN `unmatched`: con ejercicios sin match `_assign` corta antes de
/// escribir y el test no probaría nada.
ParsedPlan _plan() => const ParsedPlan(
      name: 'Plan Test',
      daysPerWeek: 1,
      durationWeeks: 4,
      level: ExperienceLevel.intermediate,
      days: [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Sentadilla',
              exerciseId: 'ex-1',
              exerciseName: 'Sentadilla',
              muscleGroup: 'Legs',
              sets: 3,
              repsMin: 10,
              repsMax: 12,
            ),
          ],
        ),
      ],
      unmatched: [],
    );

GoRouter _router() => GoRouter(
      initialLocation: '/preview',
      routes: [
        GoRoute(
          path: '/preview',
          builder: (_, __) => const Scaffold(body: CoachHubPlanPreviewScreen()),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const Scaffold(body: Text('DASHBOARD')),
        ),
        GoRoute(
          path: '/upload-plan',
          builder: (_, __) => const Scaffold(body: Text('UPLOAD')),
        ),
      ],
    );

List<Override> _overrides(RoutineRepository repo) => [
      userProfileProvider.overrideWith((ref) => Stream.value(_trainer())),
      currentUidProvider.overrideWithValue(_trainerUid),
      routineRepositoryProvider.overrideWithValue(repo),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(_atletas.keys.map(_link).toList()),
      ),
      for (final entry in _atletas.entries)
        userPublicProfileProvider(entry.key).overrideWith(
          (ref) => Stream.value(
            UserPublicProfile(uid: entry.key, displayName: entry.value),
          ),
        ),
      parsedPlanProvider.overrideWith((ref) => _plan()),
    ];

Future<void> _pumpPreview(WidgetTester tester, RoutineRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo),
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: _router(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Selecciona a los tres alumnos y aprieta ASIGNAR.
Future<void> _seleccionarTodosYAsignar(WidgetTester tester) async {
  for (final nombre in _atletas.values) {
    await tester.tap(find.text(nombre));
    await tester.pump();
  }
  await tester.tap(find.text('ASIGNAR PLAN A 3 ATLETAS'));
}

void main() {
  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  group('Asignar un plan a varios alumnos', () {
    testWidgets(
        'las escrituras arrancan TODAS antes de que termine cualquiera '
        '(paralelo, no en serie)', (tester) async {
      final repo = _MockRoutineRepository();
      final arrancadas = <String>[];
      final pendientes = <String, Completer<Routine>>{};

      when(() => repo.createAssigned(any())).thenAnswer((inv) {
        final routine = inv.positionalArguments.first as Routine;
        final athleteId = routine.assignedTo!;
        arrancadas.add(athleteId);
        // Un future que NO resuelve: mientras siga pendiente, cualquier
        // llamada posterior sólo puede venir de código que NO esperó a ésta.
        return (pendientes[athleteId] = Completer<Routine>()).future;
      });

      await _pumpPreview(tester, repo);
      await _seleccionarTodosYAsignar(tester);
      await tester.pump();

      // EL assert del arreglo. Con el `for` + `await` de antes, acá había
      // exactamente UNA escritura arrancada: las otras dos ni existían hasta
      // que el servidor confirmara la primera. Tres esperas de red en fila.
      expect(
        arrancadas,
        equals(_atletas.keys.toList()),
        reason: 'Arrancaron ${arrancadas.length} de ${_atletas.length} '
            'escrituras con ninguna resuelta: las asignaciones se están '
            'encadenando en vez de ir juntas.',
      );

      // Y se cierra el ciclo, para no dejar futures colgados.
      for (final entry in pendientes.entries) {
        entry.value.complete(
          Routine(
            id: 'r-${entry.key}',
            name: 'Plan Test',
            level: ExperienceLevel.intermediate,
            days: const [],
            assignedTo: entry.key,
            assignedBy: _trainerUid,
          ),
        );
      }
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets(
        'el éxito va al dashboard y NO rebota a subir archivo '
        '(regresión: limpiar el plan disparaba la red de seguridad)',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        final routine = inv.positionalArguments.first as Routine;
        return routine.copyWith(id: 'r-${routine.assignedTo}');
      });

      await _pumpPreview(tester, repo);
      await _seleccionarTodosYAsignar(tester);
      await tester.pumpAndSettle();

      // El bug: `_assign` limpia `parsedPlanProvider` y NAVEGA. El plan en
      // null hacía que `build` leyera "entraron acá sin subir nada" y agendara
      // un `go('/upload-plan')` que le ganaba al `go('/dashboard')`. El PF
      // asignaba bien, veía el cartel de éxito, y volvía a la pantalla de
      // subir el Excel.
      expect(find.text('UPLOAD'), findsNothing,
          reason: 'rebotó a subir archivo después de asignar correctamente');
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('si falla uno de tres, quedan seleccionados sólo los fallados',
        (tester) async {
      final repo = _MockRoutineRepository();

      when(() => repo.createAssigned(any())).thenAnswer((inv) async {
        final routine = inv.positionalArguments.first as Routine;
        final athleteId = routine.assignedTo!;
        if (athleteId == 'ath-2') throw Exception('permission-denied');
        return routine.copyWith(id: 'r-$athleteId');
      });

      await _pumpPreview(tester, repo);
      await _seleccionarTodosYAsignar(tester);
      await tester.pumpAndSettle();

      // No navega: se queda en el preview para reintentar sin re-subir.
      expect(find.text('DASHBOARD'), findsNothing);
      expect(
        find.textContaining('Plan asignado a 2 atleta(s). 1 fallaron.'),
        findsOneWidget,
      );
      // La selección se acota al que falló — el contador del botón lo delata.
      expect(find.text('ASIGNAR PLAN'), findsOneWidget);
      expect(find.textContaining('ASIGNAR A · 1 seleccionado'), findsOneWidget);
    });

    testWidgets('si fallan todos, error y sin navegar', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any()))
          .thenAnswer((_) async => throw Exception('offline'));

      await _pumpPreview(tester, repo);
      await _seleccionarTodosYAsignar(tester);
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsNothing);
      expect(find.text('No pudimos guardar el plan. Probá de nuevo.'),
          findsOneWidget);
      // La selección NO se toca: los tres siguen elegidos para reintentar.
      expect(find.text('ASIGNAR PLAN A 3 ATLETAS'), findsOneWidget);
    });
  });
}
