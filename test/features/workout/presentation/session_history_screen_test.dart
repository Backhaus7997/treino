// Tests para SessionHistoryScreen (historial pantalla completa, "Ver todo") —
// formato del volumen de la card vía formatVolumeKg (#436).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/presentation/session_history_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

Session _makeSession({
  String id = 's1',
  String routineName = 'Push A',
  double totalVolumeKg = 600.0,
  int durationMin = 45,
}) =>
    Session(
      id: id,
      uid: 'test-uid',
      routineId: 'r1',
      routineName: routineName,
      startedAt: DateTime(2025, 11, 26, 10, 30),
      finishedAt: DateTime(2025, 11, 26, 11, 15),
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

Future<void> _pumpHistoryScreen(
  WidgetTester tester, {
  required List<Session> sessions,
  // Vista del PF sobre el historial de un alumno (misma fila, otra ruta).
  String? coachAthleteId,
}) async {
  final router = GoRouter(
    initialLocation: '/workout/historial',
    routes: [
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(
        path: '/workout/historial',
        builder: (_, __) =>
            SessionHistoryScreen(coachAthleteId: coachAthleteId),
      ),
      GoRoute(
        path: '/workout/historial/:sessionId',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Detalle'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('test-uid'),
        sessionsByUidProvider.overrideWith(
          (ref, arg) => Future.value(sessions),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SessionHistoryScreen — formato de volumen', () {
    testWidgets('volumen entero muestra "600 kg", no "600.0"', (tester) async {
      await _pumpHistoryScreen(
        tester,
        sessions: [_makeSession(totalVolumeKg: 600.0)],
      );
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsOneWidget);
      expect(find.textContaining('600 kg'), findsOneWidget);
      expect(find.textContaining('600.0'), findsNothing);
    });

    testWidgets('volumen fraccionario conserva un decimal ("1.234,5 kg" en es)',
        (tester) async {
      await _pumpHistoryScreen(
        tester,
        sessions: [
          _makeSession(id: 's2', routineName: 'Pull B', totalVolumeKg: 1234.5),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1.234,5 kg'), findsOneWidget);
    });
  });

  // #1701: una sesión sólo de series por tiempo o por distancia tiene
  // `totalVolumeKg == 0`, y «0 kg» afirma un dato que no existe.
  group('SessionHistoryScreen — sesión sin carga (#1701)', () {
    /// Distancia horizontal entre el borde derecho del bloque expandido (título
    /// + fecha) y el borde izquierdo de [metric].
    double gapBeforeMetric(WidgetTester tester, Finder metric) {
      final expanded = find
          .ancestor(of: find.text('Push A'), matching: find.byType(Expanded))
          .first;
      return tester.getTopLeft(metric).dx - tester.getTopRight(expanded).dx;
    }

    testWidgets('sin volumen no muestra "0 kg": queda sólo la duración',
        (tester) async {
      await _pumpHistoryScreen(
        tester,
        sessions: [_makeSession(totalVolumeKg: 0, durationMin: 18)],
      );
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.text('18 min'), findsOneWidget);
      // Sin el volumen tampoco queda su separador: un solo hueco de 8px.
      expect(gapBeforeMetric(tester, find.text('18 min')), 8);
    });

    testWidgets('con volumen sigue mostrando volumen y duración',
        (tester) async {
      await _pumpHistoryScreen(
        tester,
        sessions: [_makeSession(totalVolumeKg: 600, durationMin: 18)],
      );
      await tester.pumpAndSettle();

      expect(find.text('600 kg'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
      expect(gapBeforeMetric(tester, find.text('600 kg')), 8);
      expect(
        tester.getTopLeft(find.text('18 min')).dx -
            tester.getTopRight(find.text('600 kg')).dx,
        8,
      );
    });

    testWidgets('vista del PF (coachAthleteId): sin volumen no muestra "0 kg"',
        (tester) async {
      await _pumpHistoryScreen(
        tester,
        coachAthleteId: 'athlete-1',
        sessions: [_makeSession(totalVolumeKg: 0, durationMin: 18)],
      );
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsOneWidget);
      expect(find.textContaining('kg'), findsNothing);
      expect(find.text('18 min'), findsOneWidget);
    });

    testWidgets('vista del PF (coachAthleteId): con volumen lo sigue mostrando',
        (tester) async {
      await _pumpHistoryScreen(
        tester,
        coachAthleteId: 'athlete-1',
        sessions: [_makeSession(totalVolumeKg: 600, durationMin: 18)],
      );
      await tester.pumpAndSettle();

      expect(find.text('600 kg'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
    });
  });
}
