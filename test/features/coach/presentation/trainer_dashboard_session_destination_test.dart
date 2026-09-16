// A dónde llevan las filas del dashboard del PF.
//
// Las dos secciones que listan entrenamientos —ENTRENARON HOY y ACTIVIDAD
// RECIENTE— hablaban de UNA sesión y te dejaban en `/coach/athlete/:id`, la
// ficha entera del alumno, donde había que ir a buscar ese entrenamiento a
// mano. No era un olvido de una: eran las dos, con el mismo `onTap` copiado.
// Arreglar una sola se ve, desde afuera, idéntico a estar arreglado — por eso
// las dos tienen su test acá.
//
// Cada test navega de verdad: monta la ruta destino y verifica que la pantalla
// que aparece sea la de la sesión. Assertear el string del path probaría que
// construimos bien una URL, no que lleve a algún lado.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/recent_activity_provider.dart';
import 'package:treino/features/coach/application/trained_today_provider.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

const _kTrainer = 't1';
const _kAthlete = 'a1';
const _kSessionId = 's-a1';

// ── Fixtures ─────────────────────────────────────────────────────────────────

Session _session() => Session(
      id: _kSessionId,
      uid: _kAthlete,
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 13),
      finishedAt: DateTime.utc(2026, 7, 28, 14),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

/// Monta [child] con una ruta destino REAL: si el `onTap` navega al lugar
/// correcto, aparece el marcador; si navega a la ficha del alumno, aparece el
/// otro. Los dos destinos existen, así que un path equivocado NO se confunde
/// con un 404 — falla diciendo a dónde fue.
Widget _wrap(Widget child, {required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/dash',
    routes: [
      GoRoute(
        path: '/dash',
        builder: (_, __) => Scaffold(body: child),
      ),
      GoRoute(
        path: '/coach/athlete/:athleteId/session/:sessionId',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text(
              'sesion:${state.pathParameters['athleteId']}'
              ':${state.pathParameters['sessionId']}',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/coach/athlete/:athleteId',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text('ficha:${state.pathParameters['athleteId']}'),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

List<Override> _baseOverrides() => [
      currentUidProvider.overrideWithValue(_kTrainer),
      userPublicProfileProvider(_kAthlete).overrideWith(
        (_) => Stream.value(
          const UserPublicProfile(uid: _kAthlete, displayName: 'Lucía'),
        ),
      ),
    ];

void main() {
  testWidgets(
      'ENTRENARON HOY: tocar una fila abre esa sesión, no la ficha del alumno',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const EntrenaronHoyListTestHarness(),
      overrides: [
        ..._baseOverrides(),
        trainedTodayProvider.overrideWithValue(
          AsyncValue.data([
            TrainedTodayEntry(athleteId: _kAthlete, session: _session()),
          ]),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lucía'));
    await tester.pumpAndSettle();

    expect(find.text('sesion:$_kAthlete:$_kSessionId'), findsOneWidget);
    expect(find.text('ficha:$_kAthlete'), findsNothing,
        reason: 'la ficha entera es el destino VIEJO: la fila habla de una '
            'sesión puntual');
  });

  testWidgets(
      'ACTIVIDAD RECIENTE: tocar una fila abre esa sesión, no la ficha del '
      'alumno', (tester) async {
    await tester.pumpWidget(_wrap(
      const ActividadRecienteListTestHarness(),
      overrides: [
        ..._baseOverrides(),
        recentActivityProvider.overrideWithValue(
          AsyncValue.data([
            RecentActivityEntry(athleteId: _kAthlete, session: _session()),
          ]),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lucía'));
    await tester.pumpAndSettle();

    expect(find.text('sesion:$_kAthlete:$_kSessionId'), findsOneWidget);
    expect(find.text('ficha:$_kAthlete'), findsNothing,
        reason: 'la SEGUNDA de las dos secciones. Tenía el mismo onTap copiado '
            'y arreglar sólo la otra se ve igual desde afuera');
  });
}
