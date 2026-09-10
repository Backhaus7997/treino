import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routine_card_grid.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

const _athlete = 'athlete-1';

Routine _routine({
  required String id,
  String name = 'Fuerza 4x',
  String? assignedTo,
  RoutineSource source = RoutineSource.trainerAssigned,
  RoutineVisibility visibility = RoutineVisibility.private,
  RoutineStatus status = RoutineStatus.active,
  int numWeeks = 1,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: source,
      assignedBy: 'trainer-1',
      assignedTo: assignedTo,
      visibility: visibility,
      status: status,
      numWeeks: numWeeks,
    );

/// Pumpea la grilla dentro de un router de verdad, para poder afirmar a dónde
/// navega cada card — que es la mitad del contrato de esta pantalla.
Future<String> _pumpYTocar(
  WidgetTester tester,
  List<Routine> routines, {
  String tocar = 'r1',
  String? displayName,
}) async {
  var destino = '/rutinas';
  final router = GoRouter(
    initialLocation: '/rutinas',
    routes: [
      GoRoute(
        path: '/rutinas',
        builder: (_, __) => Scaffold(
          body: SingleChildScrollView(
            child: RoutineCardGrid(routines: routines),
          ),
        ),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, s) {
          destino = s.uri.path;
          return const Scaffold(body: Text('editor de plan'));
        },
      ),
      GoRoute(
        path: '/template-editor/:templateId',
        builder: (_, s) {
          destino = s.uri.path;
          return const Scaffold(body: Text('editor de plantilla'));
        },
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      userPublicProfileProvider(_athlete).overrideWith(
        (ref) => Stream<UserPublicProfile?>.value(
          displayName == null
              ? null
              : UserPublicProfile(
                  uid: _athlete,
                  displayName: displayName,
                  avatarUrl: null,
                  gymId: null,
                ),
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(Key('routine_card_$tocar')));
  await tester.pumpAndSettle();
  return destino;
}

void main() {
  _menuDeRutinasTests();
  group('RoutineCardGrid — etiquetas', () {
    testWidgets('nombre resuelto → «Asignada a Sofía»', (tester) async {
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], 'Sofía');
      expect(find.text('Asignada a Sofía'), findsOneWidget);
    });

    testWidgets('nombre SIN resolver → «Asignada», nunca un nombre falso',
        (tester) async {
      // El perfil puede tardar o no existir (cuenta borrada). La card no
      // puede inventar un nombre ni decir «Usuario eliminado»: dice lo único
      // que sabe con certeza, que está asignada.
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], null);
      expect(find.text('Asignada'), findsOneWidget);
      expect(find.textContaining('Asignada a'), findsNothing);
    });

    testWidgets('una plantilla dice «Plantilla» y no habla de alumnos',
        (tester) async {
      await _pumpSoloGrilla(
        tester,
        [_routine(id: 'r1', source: RoutineSource.trainerTemplate)],
        null,
      );
      expect(find.text('Plantilla'), findsOneWidget);
      expect(find.textContaining('Asignada'), findsNothing);
    });

    testWidgets('pública y archivada se acumulan', (tester) async {
      await _pumpSoloGrilla(
        tester,
        [
          _routine(
            id: 'r1',
            source: RoutineSource.trainerTemplate,
            visibility: RoutineVisibility.public,
            status: RoutineStatus.archived,
          )
        ],
        null,
      );
      expect(find.text('Plantilla'), findsOneWidget);
      expect(find.text('Pública'), findsOneWidget);
      expect(find.text('Archivada'), findsOneWidget);
    });

    testWidgets('el resumen dice el split y las semanas', (tester) async {
      await _pumpSoloGrilla(tester, [_routine(id: 'r1', numWeeks: 4)], null);
      expect(find.text('PPL · 4 semanas'), findsOneWidget);
    });
  });

  group('RoutineCard — el menú de la rutina', () {
    testWidgets('sobre un PLAN, archivar se llama «Sacársela a {nombre}»',
        (tester) async {
      // Es la MISMA operación —archivar la copia del alumno— con el nombre de
      // lo que el PF vino a hacer. Con la palabra «Archivar» no la encontraba:
      // llegó a pedir «desasignar» como función nueva, que las reglas no
      // permiten (`assignedTo` es inmutable) y que no hace falta.
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], 'Sofía');

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();

      expect(find.text('Sacársela a Sofía'), findsOneWidget);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Eliminar'), findsOneWidget);
    });

    testWidgets('sobre una PLANTILLA sigue diciendo «Archivar»',
        (tester) async {
      // Una plantilla no tiene a quién sacársela. «Archivar» describe bien lo
      // que pasa: sale de tu biblioteca.
      await _pumpSoloGrilla(
        tester,
        [_routine(id: 'r1', source: RoutineSource.trainerTemplate)],
        null,
      );

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();

      expect(find.text('Archivar'), findsOneWidget);
      expect(find.textContaining('Sacársela'), findsNothing);
    });

    testWidgets('sin nombre resuelto dice «al alumno», nunca un uid',
        (tester) async {
      // Mismo criterio que las etiquetas: mientras el perfil carga —o si la
      // cuenta se borró— no se inventa un nombre ni se filtra el uid a la UI.
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], null);

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();

      expect(find.text('Sacársela al alumno'), findsOneWidget);
      expect(find.textContaining(_athlete), findsNothing);
    });

    testWidgets('el diálogo de sacársela NO promete que la plantilla queda',
        (tester) async {
      // La tentación del diseño original era tranquilizar con «tu plantilla no
      // se toca». Sería verdad SÓLO si el plan hubiera salido de una
      // plantilla, y la rutina no guarda de qué doc se copió:
      // `createAssigned` se llama desde tres pantallas que arman el plan a
      // mano. Un cartel que tranquiliza con algo que puede ser falso es peor
      // que no tenerlo (AGENTS.md §11.1).
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], 'Sofía');

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sacársela a Sofía'));
      await tester.pumpAndSettle();

      expect(find.textContaining('plantilla'), findsNothing);
      // Lo que sí es cierto siempre, y es lo que frena el miedo real.
      expect(find.textContaining('ya hizo se conservan'), findsOneWidget);
      expect(find.textContaining('Archivadas'), findsOneWidget);
    });

    testWidgets('una YA archivada no ofrece archivar de nuevo', (tester) async {
      await _pumpSoloGrilla(
        tester,
        [_routine(id: 'r1', status: RoutineStatus.archived)],
        null,
      );

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();

      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Recuperar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
    });

    testWidgets('borrar un PLAN ASIGNADO avisa que rompe el historial',
        (tester) async {
      // Ésta es la advertencia que justifica que archivar siga existiendo. Un
      // plan asignado pudo entrenarse, y las sesiones del alumno apuntan a
      // ESTE documento: borrarlo las deja sin referencia, que es exactamente
      // lo que ADR-USR-04 evita. Un «esto no se puede deshacer» genérico no
      // dice eso.
      await _pumpSoloGrilla(
          tester, [_routine(id: 'r1', assignedTo: _athlete)], 'Sofía');

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('quedan sin referencia'), findsOneWidget);
      expect(find.textContaining('archivala'), findsOneWidget);
    });

    testWidgets('borrar una PLANTILLA no inventa un historial que no existe',
        (tester) async {
      // Una plantilla nunca se entrenó: el alumno entrena una copia asignada.
      // Advertirle sobre entrenamientos perdidos sería un susto falso, y una
      // advertencia falsa es peor que ninguna (AGENTS.md §11.1).
      await _pumpSoloGrilla(
        tester,
        [_routine(id: 'r1', source: RoutineSource.trainerTemplate)],
        null,
      );

      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('quedan sin referencia'), findsNothing);
      expect(find.textContaining('No se puede recuperar'), findsOneWidget);
    });
  });

  group('RoutineCardGrid — a dónde entra cada card', () {
    testWidgets('un PLAN va al editor de planes, con su alumno en la URL',
        (tester) async {
      final destino = await _pumpYTocar(
        tester,
        [_routine(id: 'r1', assignedTo: _athlete)],
        displayName: 'Sofía',
      );
      expect(destino, '/routine-editor/$_athlete/r1');
    });

    testWidgets('una PLANTILLA va al editor de plantillas', (tester) async {
      // No es un detalle de routing: un plan se guarda por `updateAssigned` y
      // necesita el alumno; una plantilla va por `updateTemplate` y no tiene.
      // Mandarla al editor de planes la haría pedir un `athleteId` que no
      // existe.
      final destino = await _pumpYTocar(
        tester,
        [_routine(id: 'r1', source: RoutineSource.trainerTemplate)],
      );
      expect(destino, '/template-editor/r1');
    });
  });
}

/// Igual que [_pumpYTocar] pero sin navegar — para afirmar sobre la card.
void _menuDeRutinasTests() {
  group('RoutineCardGrid — el menú ofrece SÓLO lo que es válido', () {
    Future<void> abrirMenu(WidgetTester tester, Routine r) async {
      await _pumpSoloGrilla(tester, [r], 'Sofía');
      await tester.tap(find.byTooltip('Opciones de la rutina'));
      await tester.pumpAndSettle();
    }

    // Publicar hace un flip de `visibility`, y la regla de Firestore lo
    // restringe a docs `trainer-template` del dueño. Sobre una rutina asignada
    // el ítem sería un botón roto POR CONTRATO: el PF lo aprieta, ve un error
    // y no aprende por qué.
    testWidgets('una rutina ASIGNADA no ofrece publicar ni asignar',
        (tester) async {
      await abrirMenu(
        tester,
        _routine(id: 'r1', assignedTo: _athlete),
      );

      expect(find.text('Publicar en la comunidad'), findsNothing);
      expect(find.text('Despublicar'), findsNothing);
      expect(find.text('Asignar a un alumno'), findsNothing);
      expect(find.text('Sacársela a Sofía'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
    });

    testWidgets('una PLANTILLA privada ofrece asignar y publicar',
        (tester) async {
      await abrirMenu(
        tester,
        _routine(id: 'r1', source: RoutineSource.trainerTemplate),
      );

      expect(find.text('Asignar a un alumno'), findsOneWidget);
      expect(find.text('Publicar en la comunidad'), findsOneWidget);
      expect(find.text('Despublicar'), findsNothing);
    });

    // El ítem dice lo CONTRARIO del estado actual: es la acción, no la
    // etiqueta del estado. Con la plantilla ya pública, ofrecer «Publicar»
    // sería prometer algo que ya pasó.
    testWidgets('una PLANTILLA pública ofrece despublicar', (tester) async {
      await abrirMenu(
        tester,
        _routine(
          id: 'r1',
          source: RoutineSource.trainerTemplate,
          visibility: RoutineVisibility.public,
        ),
      );

      expect(find.text('Despublicar'), findsOneWidget);
      expect(find.text('Publicar en la comunidad'), findsNothing);
    });

    // Archivada = fuera de circulación. Asignarla o publicarla la devolvería a
    // circulación por la puerta de atrás, sin desarchivarla. Lo que SÍ ofrece
    // es desarchivarla por la puerta de adelante.
    testWidgets('una plantilla ARCHIVADA ofrece recuperar y eliminar',
        (tester) async {
      await abrirMenu(
        tester,
        _routine(
          id: 'r1',
          source: RoutineSource.trainerTemplate,
          status: RoutineStatus.archived,
        ),
      );

      expect(find.text('Asignar a un alumno'), findsNothing);
      expect(find.text('Publicar en la comunidad'), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Recuperar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
    });

    // Recuperar un PLAN es visible para otra persona: vuelve al perfil del
    // alumno. Y el alumno lo lee aunque el vínculo haya terminado —la regla de
    // lectura mira `assignedTo`, no el link— así que el diálogo NOMBRA a quién
    // se lo está devolviendo. Ese nombre es el guard.
    testWidgets('recuperar un PLAN confirma nombrando al alumno',
        (tester) async {
      await abrirMenu(
        tester,
        _routine(
          id: 'r1',
          assignedTo: _athlete,
          status: RoutineStatus.archived,
        ),
      );

      await tester.tap(find.text('Recuperar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Devolverle «Fuerza 4x» a Sofía?'), findsOneWidget);
      expect(find.textContaining('Vuelve a su perfil'), findsOneWidget);
      expect(find.text('Devolvérsela'), findsOneWidget);
    });
  });
}

Future<void> _pumpSoloGrilla(
  WidgetTester tester,
  List<Routine> routines,
  String? displayName,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      userPublicProfileProvider(_athlete).overrideWith(
        (ref) => Stream<UserPublicProfile?>.value(
          displayName == null
              ? null
              : UserPublicProfile(
                  uid: _athlete,
                  displayName: displayName,
                  avatarUrl: null,
                  gymId: null,
                ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoutineCardGrid(routines: routines),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
