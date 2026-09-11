// Suite de la sección Rutinas DESPUÉS de que dejó de listar personas.
//
// La versión anterior tenía 24 tests sobre un roster: nombres de alumnos,
// gimnasio, pill de estado del vínculo, conteo de rutinas activas por persona,
// y el toggle Tabla/Cards de esa lista. Ninguno describía algo que siga
// existiendo — la pantalla ya no tiene alumnos —, así que se reemplazan en vez
// de portarse. Lo que SÍ sobrevive está cubierto acá: loading, error, vacío,
// filtros con sus conteos, y la búsqueda.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

const _trainer = 'trainer-1';
const _athlete = 'athlete-1';

Routine _rutina({
  required String id,
  required String name,
  String split = 'PPL',
  String? assignedTo,
  RoutineSource source = RoutineSource.trainerAssigned,
  RoutineVisibility visibility = RoutineVisibility.private,
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: name,
      split: split,
      level: ExperienceLevel.beginner,
      days: const [],
      source: source,
      assignedBy: _trainer,
      assignedTo: assignedTo,
      visibility: visibility,
      status: status,
    );

/// Un plan asignado, una plantilla privada, una plantilla pública y una
/// archivada: las cuatro formas que los chips tienen que separar.
List<Routine> _mezcla() => [
      _rutina(id: 'r-plan', name: 'Plan de Sofía', assignedTo: _athlete),
      _rutina(
        id: 'r-tpl',
        name: 'Hipertrofia base',
        split: 'Full Body',
        source: RoutineSource.trainerTemplate,
      ),
      _rutina(
        id: 'r-pub',
        name: 'Fuerza para principiantes',
        source: RoutineSource.trainerTemplate,
        visibility: RoutineVisibility.public,
      ),
      _rutina(
        id: 'r-arch',
        name: 'Plan viejo',
        assignedTo: _athlete,
        status: RoutineStatus.archived,
      ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  List<Routine>? rutinas,
  Object? error,
  bool loading = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/rutinas',
    routes: [
      GoRoute(
        path: '/rutinas',
        builder: (_, __) => const Scaffold(body: RutinasScreen()),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, __) => const Scaffold(body: Text('EDITOR PLAN')),
      ),
      GoRoute(
        path: '/template-editor/:templateId',
        builder: (_, __) => const Scaffold(body: Text('EDITOR PLANTILLA')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_trainer),
        routinesAuthoredByProvider.overrideWith((ref, uid) {
          if (loading) return Completer<List<Routine>>().future;
          if (error != null) return Future<List<Routine>>.error(error);
          return Future.value(rutinas ?? const <Routine>[]);
        }),
        userPublicProfileProvider(_athlete).overrideWith(
          (ref) => Stream.value(const UserPublicProfile(
            uid: _athlete,
            displayName: 'Sofía',
            avatarUrl: null,
            gymId: null,
          )),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  if (loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  group('RutinasScreen — estados', () {
    testWidgets('mientras carga muestra el esqueleto', (tester) async {
      await _pump(tester, loading: true);
      expect(find.textContaining('No pudimos cargar'), findsNothing);
      expect(find.textContaining('Todavía no creaste'), findsNothing);
    });

    testWidgets('si falla lo DICE, no muestra una lista vacía', (tester) async {
      // Un error servido como «no tenés rutinas» sería una afirmación falsa
      // sobre el trabajo del PF (AGENTS.md §11.1).
      await _pump(tester, error: Exception('boom'));
      expect(find.text('No pudimos cargar tus rutinas.'), findsOneWidget);
    });

    testWidgets('sin rutinas dice que no creó ninguna', (tester) async {
      await _pump(tester, rutinas: const []);
      expect(find.text('Todavía no creaste ninguna rutina.'), findsOneWidget);
    });
  });

  group('RutinasScreen — lista RUTINAS, no personas', () {
    testWidgets('muestra planes Y plantillas en la misma grilla',
        (tester) async {
      // El cambio de fondo. Antes esta pantalla listaba alumnos, así que una
      // plantilla sin asignar —que no le pertenece a nadie— no aparecía en
      // ningún lado del Hub salvo en Biblioteca.
      await _pump(tester, rutinas: _mezcla());

      expect(find.text('Plan de Sofía'), findsOneWidget);
      expect(find.text('Hipertrofia base'), findsOneWidget);
      expect(find.text('Fuerza para principiantes'), findsOneWidget);
    });

    testWidgets('el subtítulo ya no habla de elegir un alumno', (tester) async {
      await _pump(tester, rutinas: _mezcla());
      expect(find.textContaining('Elegí un alumno'), findsNothing);
    });
  });

  group('RutinasScreen — los dos bloques', () {
    // El corte de §4.4: una plantilla se reutiliza, la copia de un alumno tiene
    // dueño. Con 20 alumnos y 5 rutinas cada uno, mezcladas, las plantillas del
    // PF son el 5% de una grilla de 100 tarjetas.
    testWidgets('separa «Mis plantillas» de lo que entrena cada alumno',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());

      expect(find.text('MIS PLANTILLAS'), findsOneWidget);
      expect(find.text('LO QUE ENTRENA CADA ALUMNO'), findsOneWidget);
    });

    testWidgets('las asignadas van bajo el nombre de su alumno',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());

      // El nombre aparece DOS veces y las dos son correctas: como encabezado
      // del grupo, y dentro de la card como etiqueta «Asignada a Sofía».
      expect(find.text('Sofía'), findsOneWidget);
      expect(find.text('Asignada a Sofía'), findsOneWidget);
    });

    testWidgets('sin perfil resuelto el grupo dice «Alumno», nunca el uid',
        (tester) async {
      // Mismo criterio que las etiquetas de la card. El perfil puede tardar o
      // no existir (cuenta borrada); el encabezado no puede inventar un nombre
      // ni filtrar el uid a la pantalla.
      await _pump(tester, rutinas: [
        _rutina(
          id: 'r-x',
          name: 'Plan de alguien',
          assignedTo: 'athlete-sin-perfil',
        ),
      ]);

      expect(find.text('Alumno'), findsOneWidget);
      expect(find.textContaining('athlete-sin-perfil'), findsNothing);
    });

    testWidgets('un bloque sin contenido no dibuja su encabezado',
        (tester) async {
      // Un PF que todavía no armó ninguna plantilla no tiene por qué ver un
      // título «MIS PLANTILLAS» sobre el vacío.
      await _pump(tester, rutinas: [
        _rutina(id: 'r-plan', name: 'Plan de Sofía', assignedTo: _athlete),
      ]);

      expect(find.text('MIS PLANTILLAS'), findsNothing);
      expect(find.text('LO QUE ENTRENA CADA ALUMNO'), findsOneWidget);
    });

    // CANDADO del predicado único. Los chips que estos bloques reemplazan
    // usaban DOS predicados —«Plantillas» miraba `source`, «Asignadas» miraba
    // `assignedTo`— y una rutina donde discreparan caía en los dos o, peor, en
    // ninguno: desaparecía de la pantalla sin que nada fallara.
    //
    // Este fixture es justamente esa rutina incoherente (un `trainer-template`
    // CON alumno, que las reglas no permiten crear pero que un doc viejo o un
    // import podría tener). Tiene que aparecer exactamente una vez.
    testWidgets('una rutina incoherente igual cae en un bloque, y en uno solo',
        (tester) async {
      await _pump(tester, rutinas: [
        _rutina(
          id: 'r-raro',
          name: 'Rutina incoherente',
          source: RoutineSource.trainerTemplate,
          assignedTo: _athlete,
        ),
      ]);

      expect(find.text('Rutina incoherente'), findsOneWidget);
      expect(find.text('MIS PLANTILLAS'), findsNothing);
      expect(find.text('LO QUE ENTRENA CADA ALUMNO'), findsOneWidget);
    });
  });

  group('RutinasScreen — filtros', () {
    testWidgets('«Vigentes» esconde las archivadas', (tester) async {
      // Mismo criterio que el chip equivalente del roster de Alumnos con los
      // inactivos: lo archivado tiene su propio chip y no compite por la
      // atención con lo que está en uso.
      await _pump(tester, rutinas: _mezcla());
      expect(find.text('Plan viejo'), findsNothing);
      expect(find.text('Plan de Sofía'), findsOneWidget);
    });

    // «Plantillas» y «Asignadas» ya no son chips: son los dos bloques. Un chip
    // que muestra exactamente el contenido de un bloque que ya está en pantalla
    // no filtra nada, sólo esconde el otro.
    testWidgets('ya no hay chips de Plantillas ni de Asignadas',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());
      expect(find.text('Plantillas'), findsNothing);
      expect(find.text('Asignadas'), findsNothing);
      expect(find.text('Todas'), findsNothing);
    });

    testWidgets('«Públicas» deja sólo la publicada', (tester) async {
      await _pump(tester, rutinas: _mezcla());
      await tester.tap(find.text('Públicas'));
      await tester.pumpAndSettle();

      expect(find.text('Fuerza para principiantes'), findsOneWidget);
      expect(find.text('Hipertrofia base'), findsNothing);
    });

    testWidgets('«Archivadas» es el ÚNICO chip que las muestra',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());
      await tester.tap(find.text('Archivadas'));
      await tester.pumpAndSettle();

      expect(find.text('Plan viejo'), findsOneWidget);
      expect(find.text('Plan de Sofía'), findsNothing);
    });
  });

  group('RutinasScreen — búsqueda', () {
    testWidgets('filtra por nombre de la rutina', (tester) async {
      await _pump(tester, rutinas: _mezcla());
      await tester.enterText(
          find.byKey(const Key('rutinas_search_field')), 'hipertrofia');
      await tester.pumpAndSettle();

      expect(find.text('Hipertrofia base'), findsOneWidget);
      expect(find.text('Plan de Sofía'), findsNothing);
    });

    testWidgets('también por split, que es lo otro que uno recuerda',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());
      await tester.enterText(
          find.byKey(const Key('rutinas_search_field')), 'full body');
      await tester.pumpAndSettle();

      expect(find.text('Hipertrofia base'), findsOneWidget);
      expect(find.text('Plan de Sofía'), findsNothing);
    });

    testWidgets('sin resultados lo dice, no deja la grilla en blanco',
        (tester) async {
      await _pump(tester, rutinas: _mezcla());
      await tester.enterText(
          find.byKey(const Key('rutinas_search_field')), 'zzzz');
      await tester.pumpAndSettle();

      expect(
        find.text('No encontramos rutinas con esos filtros.'),
        findsOneWidget,
      );
    });
  });
}
