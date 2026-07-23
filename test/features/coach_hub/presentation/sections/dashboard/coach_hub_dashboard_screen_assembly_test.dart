// WU-06 (Fase 2) — Ensamble del Dashboard: motion staggered, responsive
// two-column/stack y spacing tokenizado final.
//
// RED → GREEN: cubre el contrato de ensamble de
// coach_hub_dashboard_screen.dart (ADR-D2-05, WU-06).
//
// SCENARIO-ASM-01: wide (>=900, alto finito) → layout de dos columnas
//   (IntrinsicHeight envolviendo la columna derecha).
// SCENARIO-ASM-02: narrow (<900) → stack de una sola columna (sin
//   IntrinsicHeight envolviendo la columna derecha).
// SCENARIO-ASM-03: entrada staggered (TreinoFadeSlideIn) no rompe
//   pumpAndSettle con reduce-motion activo — todas las secciones eager
//   quedan visibles.
// SCENARIO-ASM-04: KPI strip narrow usa Wrap (sin scroll horizontal).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ──────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

// ─── Test helpers ────────────────────────────────────────────────────────────

List<Override> _fullOverrides() => <Override>[
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value(const <TrainerLink>[])),
      userProfileProvider
          .overrideWith((ref) => Stream.value(_trainerProfile())),
      currentUidProvider.overrideWithValue('trainer-1'),
      pagosBucketsProvider.overrideWith(
        (ref) => const AsyncData(PagosBuckets(
          vencidos: [],
          porVencer: [],
          pagados: [],
          todos: [],
        )),
      ),
      totalUnreadCountProvider.overrideWithValue(0),
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => Stream.value(const <Appointment>[]),
      ),
      aggregateAdherenceProvider.overrideWith((ref) async => null),
      inactivosProvider.overrideWith(
        (ref) => Future.value(const InactivosResult(inactiveAthleteIds: [])),
      ),
    ];

/// Pumps [CoachHubDashboardScreen] con el viewport de test fijado a [size] —
/// el `LayoutBuilder` del screen deriva sus constraints del tamaño real de
/// ventana (mismo patrón que `coach_hub_dashboard_in_shell_test.dart`).
Future<void> _pumpAt(
  WidgetTester tester, {
  required Size size,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: _fullOverrides(),
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: CoachHubDashboardScreen()),
      ),
    ),
  );
}

void main() {
  group('SCENARIO-ASM-01 — wide usa layout de dos columnas', () {
    testWidgets('IntrinsicHeight envuelve la columna derecha', (tester) async {
      await _pumpAt(tester, size: const Size(1400, 900), reduceMotion: true);
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.byType(DashboardRightColumn),
          matching: find.byType(IntrinsicHeight),
        ),
        findsOneWidget,
      );
    });
  });

  group('SCENARIO-ASM-02 — narrow usa stack de una columna', () {
    testWidgets('sin IntrinsicHeight envolviendo la columna derecha',
        (tester) async {
      await _pumpAt(tester, size: const Size(700, 1400), reduceMotion: true);
      await tester.pumpAndSettle();

      expect(find.byType(DashboardRightColumn), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(DashboardRightColumn),
          matching: find.byType(IntrinsicHeight),
        ),
        findsNothing,
      );
    });
  });

  group('SCENARIO-ASM-03 — entrada staggered no rompe pumpAndSettle', () {
    testWidgets('reduce-motion activo → secciones eager visibles de entrada',
        (tester) async {
      await _pumpAt(tester, size: const Size(1400, 900), reduceMotion: true);
      await tester.pumpAndSettle();

      // Al menos: alert banner, welcome card, KPI strip, columna izquierda y
      // las 3 cards de la columna derecha (+ 4 TreinoEmptyState internos:
      // pendientes, proximas sesiones, vencimientos, inactivos — todos
      // stubeados vacíos).
      expect(find.byType(TreinoFadeSlideIn), findsAtLeastNWidgets(11));
      expect(find.byKey(const Key('alert_banner_root')), findsOneWidget);
      expect(find.byKey(const Key('welcome_card_root')), findsOneWidget);
    });

    testWidgets('sin reduce-motion → pumpAndSettle también converge',
        (tester) async {
      await _pumpAt(tester, size: const Size(1400, 900));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alert_banner_root')), findsOneWidget);
    });
  });

  group('SCENARIO-ASM-04 — KPI strip narrow usa Wrap', () {
    testWidgets('sin scroll horizontal en narrow', (tester) async {
      await _pumpAt(tester, size: const Size(700, 1400), reduceMotion: true);
      await tester.pumpAndSettle();

      expect(find.byType(Wrap), findsWidgets);
    });
  });
}
