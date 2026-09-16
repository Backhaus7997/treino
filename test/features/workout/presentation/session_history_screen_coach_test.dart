// El historial de sesiones visto por el PF.
//
// La propiedad bajo prueba no es cosmética: hasta acá las sesiones EN CURSO y
// las INCOMPLETAS no aparecían en ninguna superficie del PF. El push de
// molestia sale al CREARSE el reporte, así que un alumno que reporta un dolor y
// abandona el entreno a mitad deja una sesión que se cierra sola como
// incompleta — y el PF recibe un aviso sobre un dolor cuyo registro no puede
// encontrar por ningún camino. Para siempre, no "hasta que termine".
//
// Cada aserción del modo PF va con su control en modo dueño: el filtro del
// alumno NO se tocó, y un test que no lo verifique no distingue "el PF ve más"
// de "se rompió el filtro de todos".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/presentation/session_history_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kOwner = 'owner-uid';
const _kAthlete = 'athlete-1';

/// Terminada y completa — la única que el ALUMNO ve.
Session _completa({String id = 's-ok', String name = 'Push'}) => Session(
      id: id,
      uid: _kAthlete,
      routineId: 'r1',
      routineName: name,
      startedAt: DateTime.utc(2026, 5, 19, 13),
      finishedAt: DateTime.utc(2026, 5, 19, 14),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

/// EN CURSO: `finishedAt == null`. Es la que recibe el push de molestia.
Session _enCurso({String id = 's-live'}) => Session(
      id: id,
      uid: _kAthlete,
      routineId: 'r1',
      routineName: 'Piernas',
      startedAt: DateTime.utc(2026, 5, 20, 13),
      status: SessionStatus.active,
      wasFullyCompleted: false,
    );

/// Terminada pero SIN completar — la que el barrido de zombis cierra sola.
Session _incompleta({String id = 's-zombie'}) => Session(
      id: id,
      uid: _kAthlete,
      routineId: 'r1',
      routineName: 'Espalda',
      startedAt: DateTime.utc(2026, 5, 18, 13),
      finishedAt: DateTime.utc(2026, 5, 18, 13, 20),
      status: SessionStatus.finished,
      wasFullyCompleted: false,
    );

Widget _wrap({
  required List<Session> sessions,
  String? coachAthleteId,
}) {
  final router = GoRouter(
    initialLocation: '/h',
    routes: [
      GoRoute(
        path: '/h',
        builder: (_, __) =>
            SessionHistoryScreen(coachAthleteId: coachAthleteId),
      ),
      GoRoute(
        path: '/coach/athlete/:athleteId/session/:sessionId',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text('sesion:${state.pathParameters['sessionId']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/workout/historial/:sessionId',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text('propia:${state.pathParameters['sessionId']}'),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kOwner),
      sessionsByUidProvider.overrideWith((ref, uid) async => sessions),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('modo PF: lista la sesión EN CURSO', (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_completa(), _enCurso()],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Piernas'), findsOneWidget,
        reason: 'el push de molestia llega con la sesión abierta; si no está '
            'en la lista, el PF no tiene dónde encontrarla');
  });

  testWidgets('modo PF: lista la sesión terminada SIN completar',
      (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_completa(), _incompleta()],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Espalda'), findsOneWidget,
        reason: 'una sesión abandonada se cierra como incompleta y hasta ahora '
            'quedaba invisible PARA SIEMPRE');
  });

  testWidgets(
      'CONTROL NEGATIVO — modo dueño: NO lista ni la en curso ni la incompleta',
      (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_completa(), _enCurso(), _incompleta()],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Piernas'), findsNothing,
        reason: 'el filtro del alumno NO se tocó; sin este control, "el PF ve '
            'más" no se distingue de "se rompió el filtro de todos"');
    expect(find.text('Espalda'), findsNothing);
  });

  testWidgets('modo PF: el estado se dice, no se pinta un ✓ de "hecho"',
      (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_enCurso()],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('En curso'), findsOneWidget);
    expect(find.byIcon(TreinoIcon.checkCircleFill), findsNothing,
        reason: 'un ✓ lleno sobre una sesión viva es una pantalla afirmando '
            'más de lo que sabe');
  });

  testWidgets('las marcas de reporte salen de feedbackCounts', (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [
        _completa().copyWith(
          feedbackCounts: const {
            ExerciseFeedbackKind.discomfort: 2,
            ExerciseFeedbackKind.comment: 3,
          },
        ),
      ],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(TreinoIcon.warning), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(TreinoIcon.chat), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('CONTROL — sin reportes no se dibuja ninguna marca',
      (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_completa()],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(TreinoIcon.warning), findsNothing,
        reason: 'una marca que aparece siempre no informa nada');
    expect(find.byIcon(TreinoIcon.chat), findsNothing);
  });

  testWidgets('modo PF: tocar una fila abre la sesión en la ruta del PF',
      (tester) async {
    await tester.pumpWidget(_wrap(
      sessions: [_completa(id: 's-42')],
      coachAthleteId: _kAthlete,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.text('sesion:s-42'), findsOneWidget);
  });

  testWidgets('CONTROL — modo dueño: la fila abre SU propia ruta',
      (tester) async {
    await tester.pumpWidget(_wrap(sessions: [_completa(id: 's-42')]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.text('propia:s-42'), findsOneWidget,
        reason: 'el alumno no puede terminar en una ruta de coach');
  });

  // ── El tope del fetch, declarado (P2 de Codex en el #1153) ───────────────
  //
  // `sessionsByUidProvider` corta en `kSessionHistoryFetchLimit` y hasta acá lo
  // hacía EN SILENCIO: la lista simplemente terminaba. Una lista que termina
  // afirma «esto es todo», así que el corte mentía sobre el pasado del usuario
  // sin decir una palabra — el mismo modo de falla que AGENTS.md §11.1.
  //
  // El arreglo de fondo es paginar detrás de un cursor (anotado como follow-up
  // en el dartdoc del propio límite). Esto no lo reemplaza: declara el tope
  // mientras tanto.
  group('tope del fetch', () {
    // NO asertivo a propósito. Un cartel que afirme «hay entrenamientos más
    // viejos» es falso para quien tiene exactamente `kSessionHistoryFetchLimit`
    // sesiones, y prometer un número de filas es falso en modo alumno, donde el
    // filtro de incompletas deja menos. Lo marcó Codex en el #1161.
    const textoDelTope =
        'Puede haber entrenamientos más viejos que no entran en esta lista.';

    List<Session> completas(int n) => [
          for (int i = 0; i < n; i++) _completa(id: 's-$i', name: 'Push $i'),
        ];

    Future<void> hastaElFinal(WidgetTester tester) =>
        tester.scrollUntilVisible(find.text(textoDelTope), 600);

    // Control negativo del de abajo. Sin éste, un pie incondicional pasaría
    // igual — y le diría a TODO usuario que le falta historial, que es una
    // mentira nueva en lugar de la vieja.
    testWidgets('no se declara nada si la lista no llegó al tope',
        (tester) async {
      await tester.pumpWidget(_wrap(sessions: completas(3)));
      await tester.pumpAndSettle();

      expect(find.text(textoDelTope), findsNothing);
    });

    testWidgets('al llegar al tope, el pie lo dice', (tester) async {
      await tester.pumpWidget(
        _wrap(sessions: completas(kSessionHistoryFetchLimit)),
      );
      await tester.pumpAndSettle();

      await hastaElFinal(tester);

      expect(find.text(textoDelTope), findsOneWidget);
    });

    // El punto sutil, y la razón por la que la comparación va contra `all` y no
    // contra la lista ya filtrada: el tope lo aplica el FETCH, antes de que
    // `_visibles` descarte nada. Mirando `visibles`, el modo ALUMNO —que filtra
    // las incompletas— nunca alcanzaría el número y el aviso no saldría jamás
    // justo para quien más historial tiene.
    testWidgets('el modo alumno lo declara aunque su filtro achique la lista',
        (tester) async {
      final sessions = [
        ...completas(kSessionHistoryFetchLimit - 1),
        _incompleta(),
      ];

      await tester.pumpWidget(_wrap(sessions: sessions));
      await tester.pumpAndSettle();

      await hastaElFinal(tester);

      expect(find.text(textoDelTope), findsOneWidget);
    });
  });
}
