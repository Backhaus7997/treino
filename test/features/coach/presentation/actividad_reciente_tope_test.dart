// El tope de «Actividad reciente» y su «Ver todo» (plan del PF §3).
//
// El dashboard es un resumen: arriba tiene «Próximas sesiones» y «Entrenaron
// hoy», abajo «Pagos por cobrar». Un feed que crece hasta llenar la pantalla
// empuja todo eso debajo del pliegue.
//
// Hasta este cambio había UN solo número (8) haciendo dos trabajos: cuántas
// entradas trae el provider y cuántas se ven. Ahora son dos —
// [kRecentActivityMaxEntries] (datos) y [kRecentActivityPreviewCount]
// (presentación)— y este archivo cubre el segundo. El primero se testea en
// `test/features/coach/application/recent_activity_provider_test.dart`.
//
// El «Ver todo» se testea en sus DOS direcciones a propósito. Que aparezca con
// muchas entradas no prueba nada solo: un trailing incondicional pasaría ese
// test igual. Lo que lo hace valer es el control negativo de al lado — con
// pocas entradas NO tiene que estar, porque un botón que promete más y lleva a
// la misma lista entrena al PF a ignorarlo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/recent_activity_provider.dart';
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

Session _session(int i) => Session(
      id: 's$i',
      uid: 'a$i',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 13).add(Duration(hours: i)),
      finishedAt: DateTime.utc(2026, 7, 28, 14).add(Duration(hours: i)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

/// [n] entradas, cada una de un alumno distinto — así cada fila tiene un nombre
/// propio y contar nombres cuenta filas.
List<RecentActivityEntry> _entries(int n) => [
      for (int i = 0; i < n; i++)
        RecentActivityEntry(athleteId: 'a$i', session: _session(i)),
    ];

List<Override> _overrides(int n) => [
      currentUidProvider.overrideWithValue(_kTrainer),
      for (int i = 0; i < n; i++)
        userPublicProfileProvider('a$i').overrideWith(
          (_) => Stream.value(
            UserPublicProfile(uid: 'a$i', displayName: 'Alumno $i'),
          ),
        ),
      recentActivityProvider.overrideWithValue(AsyncValue.data(_entries(n))),
    ];

/// Monta [child] con la ruta destino REAL del «Ver todo»: si el tap navega bien
/// aparece el marcador, y si navega a otro lado falla diciendo a dónde fue en
/// vez de confundirse con un 404.
Widget _wrap(Widget child, {required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/dash',
    routes: [
      GoRoute(path: '/dash', builder: (_, __) => Scaffold(body: child)),
      GoRoute(
        path: '/coach/actividad',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('pantalla:actividad-completa')),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('tope de presentación', () {
    testWidgets('el dashboard corta en kRecentActivityPreviewCount filas',
        (tester) async {
      const traidas = kRecentActivityPreviewCount + 3;
      await tester.pumpWidget(_wrap(
        const ActividadRecienteListTestHarness(
          limit: kRecentActivityPreviewCount,
        ),
        overrides: _overrides(traidas),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Alumno 0'), findsOneWidget);
      expect(
        find.text('Alumno ${kRecentActivityPreviewCount - 1}'),
        findsOneWidget,
        reason: 'la última que SÍ entra',
      );
      expect(
        find.text('Alumno $kRecentActivityPreviewCount'),
        findsNothing,
        reason: 'la primera que queda detrás del «Ver todo»',
      );
    });

    testWidgets('la pantalla completa no corta nada', (tester) async {
      const traidas = kRecentActivityPreviewCount + 3;
      await tester.pumpWidget(_wrap(
        // `limit: null` es lo que pasa RecentActivityScreen.
        const ActividadRecienteListTestHarness(),
        overrides: _overrides(traidas),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Alumno ${traidas - 1}'),
        findsOneWidget,
        reason: 'la última de todas, la que el dashboard esconde',
      );
    });
  });

  group('«Ver todo»', () {
    testWidgets(
        'aparece cuando hay más filas de las que entran, y lleva a la '
        'pantalla completa', (tester) async {
      await tester.pumpWidget(_wrap(
        const ActividadRecienteHeaderTestHarness(),
        overrides: _overrides(kRecentActivityPreviewCount + 1),
      ));
      await tester.pumpAndSettle();

      final verTodo = find.text('Ver todo');
      expect(verTodo, findsOneWidget);

      await tester.tap(verTodo);
      await tester.pumpAndSettle();

      expect(find.text('pantalla:actividad-completa'), findsOneWidget);
    });

    // El control negativo del de arriba: un trailing incondicional pasaría
    // aquel test igual de bien y fallaría éste.
    testWidgets('NO aparece cuando entran todas', (tester) async {
      await tester.pumpWidget(_wrap(
        const ActividadRecienteHeaderTestHarness(),
        overrides: _overrides(kRecentActivityPreviewCount),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ver todo'), findsNothing);
    });
  });
}
