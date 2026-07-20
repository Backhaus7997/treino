// Widget tests for TemplatesTab, TemplateGridCard, and TemplateDetailDialog.
// REQ-BIBW-09, REQ-BIBW-10, REQ-BIBW-11.
// SCENARIO-BIBW-09a, SCENARIO-BIBW-09b, SCENARIO-BIBW-09c,
// SCENARIO-BIBW-10a, SCENARIO-BIBW-11b.
// T-BIBW-004

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
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-templates-test';

Routine _makeRoutine(String id, String name, {int days = 3, int weeks = 8}) {
  return Routine(
    id: id,
    name: name,
    level: ExperienceLevel.intermediate,
    days: List.generate(
      days,
      (i) =>
          RoutineDay(dayNumber: i + 1, name: 'Día ${i + 1}', slots: const []),
    ),
    numWeeks: weeks,
    source: RoutineSource.trainerTemplate,
  );
}

final _templateA = _makeRoutine('tpl-a', 'Fuerza Total', days: 3, weeks: 8);
final _templateB = _makeRoutine(
  'tpl-b',
  'Hipertrofia Máxima',
  days: 4,
  weeks: 12,
);
final _templateC = _makeRoutine('tpl-c', 'Full Body Básico', days: 5, weeks: 4);

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Routine> templates = const [],
  bool loading = false,
  bool error = false,
}) {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith((ref) {
        if (loading) return const Stream.empty();
        if (error) {
          return Stream.error(Exception('templates error'));
        }
        return Stream.value(templates);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

// ── Assign-flow fixtures (PR2) ──────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

TrainerLink _activeLink(String athleteId) => TrainerLink(
  id: 'link-$athleteId',
  trainerId: _kTrainerId,
  athleteId: athleteId,
  status: TrainerLinkStatus.active,
  requestedAt: DateTime(2024, 1, 1),
);

/// Pumps [TemplatesTab] with everything the "Usar en un alumno" flow touches:
/// the templates stream, the trainer-links stream (feeds the athlete picker),
/// a mocked repository, and a public-profile override per athlete (the picker
/// tiles watch it — without an override it would hit real Firestore).
Future<void> _pumpAssignable(
  WidgetTester tester, {
  required RoutineRepository repo,
  List<Routine> templates = const [],
  List<TrainerLink> links = const [],
  Map<String, String> names = const {},
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainerId),
        trainerTemplatesStreamProvider(
          _kTrainerId,
        ).overrideWith((ref) => Stream.value(templates)),
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        routineRepositoryProvider.overrideWithValue(repo),
        for (final entry in names.entries)
          userPublicProfileProvider(entry.key).overrideWith(
            (ref) => Stream.value(
              UserPublicProfile(uid: entry.key, displayName: entry.value),
            ),
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: TemplatesTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('TemplatesTab — smoke renders', () {
    testWidgets('renders 3 template cards — SCENARIO-BIBW-09a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const TemplatesTab(),
          templates: [_templateA, _templateB, _templateC],
        ),
      );
      await tester.pumpAndSettle();

      // Names visible
      expect(find.text('Fuerza Total'), findsOneWidget);
      expect(find.text('Hipertrofia Máxima'), findsOneWidget);
      expect(find.text('Full Body Básico'), findsOneWidget);
    });

    testWidgets(
      'each card shows días/sem · semanas subtitle — SCENARIO-BIBW-09a',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrap(const TemplatesTab(), templates: [_templateA]),
        );
        await tester.pumpAndSettle();

        // templateA: 3 días, 8 semanas
        expect(find.textContaining('3 días/sem'), findsOneWidget);
        expect(find.textContaining('8 semanas'), findsOneWidget);
      },
    );

    testWidgets('singulariza día/semana cuando el conteo es 1', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final single = _makeRoutine(
        'tpl-single',
        'Plan Corto',
        days: 1,
        weeks: 1,
      );
      await tester.pumpWidget(_wrap(const TemplatesTab(), templates: [single]));
      await tester.pumpAndSettle();

      // 1 día → "día" (no "días") · 1 semana → "semana" (no "semanas").
      expect(find.text('1 día/sem · 1 semana'), findsOneWidget);
    });

    testWidgets('each card shows level — SCENARIO-BIBW-09a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      // ExperienceLevel.intermediate → displayNameEs = "Intermedio" → uppercased in chip → "INTERMEDIO"
      expect(find.textContaining('INTERMEDIO'), findsOneWidget);
    });

    testWidgets('no text matching "alumnos" anywhere — SCENARIO-BIBW-09b', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const TemplatesTab(),
          templates: [_templateA, _templateB, _templateC],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('alumnos'), findsNothing);
      expect(find.textContaining('alumno'), findsNothing);
    });

    testWidgets('shows empty-state when list is empty — SCENARIO-BIBW-09c', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const TemplatesTab(), templates: const []));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsNothing);
      expect(find.textContaining('plantilla'), findsWidgets);
    });

    testWidgets(
      'shows CircularProgressIndicator when loading — SCENARIO-BIBW-11b',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Use a Completer-based stream that never emits (stays in loading)
        final completer = Completer<List<Routine>>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUidProvider.overrideWithValue(_kTrainerId),
              trainerTemplatesStreamProvider(
                _kTrainerId,
              ).overrideWith((ref) => Stream.fromFuture(completer.future)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: TemplatesTab()),
            ),
          ),
        );
        await tester.pump(); // single frame — stream still pending

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('shows error text when stream errors — SCENARIO-BIBW-11b', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const TemplatesTab(), error: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Error'), findsOneWidget);
    });
  });

  group('TemplatesTab — template detail dialog', () {
    testWidgets('tap template card opens AlertDialog — SCENARIO-BIBW-10a', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
      'detail dialog offers Editar but no INLINE editing (edits on a screen)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrap(const TemplatesTab(), templates: [_templateA]),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Fuerza Total'));
        await tester.pumpAndSettle();

        // Editing happens on the full editor screen, not inline in the dialog:
        // an Editar action is present, but no text fields.
        expect(
          find.byKey(const Key('template_detail_edit_button')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(EditableText), findsNothing);
      },
    );

    testWidgets('detail dialog has Cerrar button that dismisses it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(const TemplatesTab(), templates: [_templateA]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      expect(find.text('Cerrar'), findsOneWidget);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('TemplatesTab — navegación al editor de plantillas', () {
    Future<void> pumpRouter(
      WidgetTester tester, {
      List<Routine> templates = const [],
    }) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/biblioteca',
        routes: [
          GoRoute(
            path: '/biblioteca',
            builder: (_, __) => const Scaffold(body: TemplatesTab()),
          ),
          // Editor stand-ins — assert navigation by the marker text.
          GoRoute(
            path: '/template-editor',
            builder: (_, __) => const Scaffold(body: Text('CREATE TEMPLATE')),
          ),
          GoRoute(
            path: '/template-editor/:id',
            builder: (_, s) =>
                Scaffold(body: Text('EDIT ${s.pathParameters['id']}')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(_kTrainerId),
            trainerTemplatesStreamProvider(
              _kTrainerId,
            ).overrideWith((ref) => Stream.value(templates)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('"Nueva plantilla" abre el editor en modo plantilla', (
      tester,
    ) async {
      await pumpRouter(tester);

      await tester.tap(find.byKey(const Key('nueva_plantilla_button')));
      await tester.pumpAndSettle();

      expect(find.text('CREATE TEMPLATE'), findsOneWidget);
    });

    testWidgets('"Editar" en el detalle abre el editor de esa plantilla', (
      tester,
    ) async {
      await pumpRouter(tester, templates: [_templateA]);

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template_detail_edit_button')));
      await tester.pumpAndSettle();

      expect(find.text('EDIT tpl-a'), findsOneWidget);
    });
  });

  group('TemplatesTab — asignar plantilla a un alumno (PR2)', () {
    testWidgets('el detalle ofrece "Usar en un alumno"', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpAssignable(tester, repo: repo, templates: [_templateA]);

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('template_detail_use_button')),
        findsOneWidget,
      );
    });

    testWidgets('usar → elegir alumno → copia la plantilla y avisa', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.assignTemplateToAthlete(
          template: _templateA,
          athleteId: 'ath-1',
        ),
      ).thenAnswer(
        (_) async => _templateA.copyWith(
          id: 'assigned-1',
          source: RoutineSource.trainerAssigned,
          assignedTo: 'ath-1',
        ),
      );

      await _pumpAssignable(
        tester,
        repo: repo,
        templates: [_templateA],
        links: [_activeLink('ath-1')],
        names: {'ath-1': 'Vicente'},
      );

      // Abre el detalle → "Usar en un alumno".
      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template_detail_use_button')));
      await tester.pumpAndSettle();

      // Se abre el picker de alumnos; elegimos uno.
      expect(find.text('ASIGNAR A UN ALUMNO'), findsOneWidget);
      await tester.tap(find.text('Vicente'));
      await tester.pumpAndSettle();

      // El repo copió la plantilla en una rutina asignada a ese alumno,
      // dejando la plantilla intacta (parity con mobile _onAssign).
      verify(
        () => repo.assignTemplateToAthlete(
          template: _templateA,
          athleteId: 'ath-1',
        ),
      ).called(1);
      expect(find.text('Plantilla asignada al alumno.'), findsOneWidget);
    });

    testWidgets('si el repo falla, muestra el snackbar de error', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.assignTemplateToAthlete(
          template: _templateA,
          athleteId: 'ath-1',
        ),
      ).thenThrow(Exception('backend down'));

      await _pumpAssignable(
        tester,
        repo: repo,
        templates: [_templateA],
        links: [_activeLink('ath-1')],
        names: {'ath-1': 'Vicente'},
      );

      await tester.tap(find.text('Fuerza Total'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template_detail_use_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vicente'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos asignar la plantilla.'), findsOneWidget);
    });
  });
}
