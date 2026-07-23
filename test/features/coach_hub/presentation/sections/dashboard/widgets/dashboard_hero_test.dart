// WU-02 — Zona hero del dashboard: DashboardAlertBanner + DashboardWelcomeCard.
//
// RED → GREEN: cubre el contrato de extracción a
// dashboard/widgets/dashboard_hero.dart (ADR-D2-05).
//
// SCENARIO-HERO-01: banner renderiza título + CTA cuando hay alertas, y el
//   tap en el CTA navega a la sección más urgente.
// SCENARIO-HERO-02: welcome card renderiza el saludo con el nombre real y
//   las 3 acciones principales navegan a sus rutas reales.
// SCENARIO-HERO-03: el anillo de adherencia muestra "--" en loading/null y
//   el porcentaje real con data.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

UserProfile _trainerProfile({String displayName = 'Joaco Trainer'}) =>
    UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
    );

Payment _vencidoPayment(String id) => Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'a1',
      amountArs: 10000,
      concept: 'Mensualidad',
      status: PaymentStatus.pending,
      createdAt: DateTime.utc(2025, 1, 1), // definitely vencido
    );

// ─── Test helpers ─────────────────────────────────────────────────────────────

/// Router mínimo: monta [child] en `/` y registra rutas stub para las
/// secciones a las que navegan el CTA del banner y las quick actions.
Future<GoRouter> _pumpWithRouter(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(path: '/pagos', builder: (_, __) => const Text('page:/pagos')),
      GoRoute(
          path: '/alumnos', builder: (_, __) => const Text('page:/alumnos')),
      GoRoute(
          path: '/biblioteca',
          builder: (_, __) => const Text('page:/biblioteca')),
      GoRoute(
          path: '/mensajes', builder: (_, __) => const Text('page:/mensajes')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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
  return router;
}

List<Override> _bannerOverrides({
  List<Payment> payments = const [],
  List<TrainerLink> links = const [],
  InactivosResult inactivos = const InactivosResult(inactiveAthleteIds: []),
}) =>
    [
      pagosBucketsProvider.overrideWith(
        (ref) => AsyncData(PagosBuckets(
          vencidos: payments,
          porVencer: const [],
          pagados: const [],
          todos: payments,
        )),
      ),
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      inactivosProvider.overrideWith((ref) async => inactivos),
    ];

List<Override> _welcomeOverrides({
  String trainerDisplayName = 'Joaco Trainer',
  double? adherenceValue,
}) =>
    [
      currentUidProvider.overrideWithValue('trainer-1'),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_trainerProfile(displayName: trainerDisplayName)),
      ),
      totalUnreadCountProvider.overrideWithValue(0),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value(const <TrainerLink>[]),
      ),
      pagosBucketsProvider.overrideWith(
        (ref) => const AsyncData(PagosBuckets(
          vencidos: [],
          porVencer: [],
          pagados: [],
          todos: [],
        )),
      ),
      trainerAppointmentsStreamProvider.overrideWith(
        (ref, key) => Stream.value(const <Appointment>[]),
      ),
      aggregateAdherenceProvider.overrideWith((ref) async => adherenceValue),
    ];

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SCENARIO-HERO-01 — DashboardAlertBanner', () {
    testWidgets(
        'renders composed title and CTA when there are alerts, '
        'tap navigates to the most urgent section', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardAlertBanner(),
        overrides: _bannerOverrides(
          payments: [_vencidoPayment('p1')],
          links: [_link(id: 'l1', status: TrainerLinkStatus.pending)],
        ),
      );

      // El título del banner se muestra en CAPS (Barlow Condensed 700).
      expect(find.textContaining('VENCIDO'), findsOneWidget);
      expect(find.byKey(const Key('alert_banner_cta')), findsOneWidget);

      await tester.tap(find.byKey(const Key('alert_banner_cta')));
      await tester.pumpAndSettle();

      // Vencidos > 0 → la sección más urgente es /pagos.
      expect(find.text('page:/pagos'), findsOneWidget);
    });

    testWidgets('hides CTA and shows "Todo al día" when all clear',
        (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardAlertBanner(),
        overrides: _bannerOverrides(),
      );

      expect(find.textContaining('TODO AL DÍA'), findsOneWidget);
      expect(find.byKey(const Key('alert_banner_cta')), findsNothing);
    });
  });

  group('SCENARIO-HERO-02 — DashboardWelcomeCard', () {
    testWidgets('renders greeting with trainer first name uppercase',
        (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(trainerDisplayName: 'Joaco Trainer'),
      );

      expect(find.textContaining('BUENAS, JOACO'), findsOneWidget);
    });

    testWidgets(
        'the 3 primary quick actions navigate to /alumnos, /biblioteca, '
        '/mensajes', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(),
      );

      await tester.tap(find.byKey(const Key('quick_action_nuevo_alumno')));
      await tester.pumpAndSettle();
      expect(find.text('page:/alumnos'), findsOneWidget);
    });

    testWidgets('crear rutina navigates to /biblioteca', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(),
      );

      await tester.tap(find.byKey(const Key('quick_action_crear_rutina')));
      await tester.pumpAndSettle();
      expect(find.text('page:/biblioteca'), findsOneWidget);
    });

    testWidgets('mensajes navigates to /mensajes', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(),
      );

      await tester.tap(find.byKey(const Key('quick_action_mensajes')));
      await tester.pumpAndSettle();
      expect(find.text('page:/mensajes'), findsOneWidget);
    });
  });

  group('SCENARIO-HERO-03 — adherence ring', () {
    testWidgets('shows "--" while loading/null', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(adherenceValue: null),
      );

      expect(find.text('--'), findsWidgets);
    });

    testWidgets('shows the real percentage with data', (tester) async {
      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(adherenceValue: 84.0),
      );

      expect(find.text('84%'), findsOneWidget);
    });
  });

  group('SCENARIO-HERO-04 — accesibilidad de teclado de los CTAs nuevos', () {
    // Remediación CRITICAL#2 (sdd-verify fase-2): _AlertBannerCta y
    // _PrimaryQuickAction envolvían un TreinoTappable crudo (sin Focus ni
    // Semantics) en vez de TreinoInteractiveState, el resolver que expone
    // el resto del kit (KpiCard, TreinoListRow) — inalcanzables por teclado
    // y no anunciados como botón a lectores de pantalla.
    testWidgets(
        'alert banner CTA: focusable, Semantics(button) y Enter activa onTap',
        (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpWithRouter(
        tester,
        const DashboardAlertBanner(),
        overrides: _bannerOverrides(payments: [_vencidoPayment('p1')]),
      );

      final semantics = tester.getSemantics(
        find.byKey(const Key('alert_banner_cta')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason:
              'el CTA del alert banner debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('alert_banner_cta'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('page:/pagos'), findsOneWidget,
          reason: 'Enter (teclado) debe activar el CTA igual que el tap');

      handle.dispose();
    });

    testWidgets(
        '"+ Nuevo alumno": focusable, Semantics(button) y Enter activa onTap',
        (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpWithRouter(
        tester,
        const DashboardWelcomeCard(),
        overrides: _welcomeOverrides(),
      );

      final semantics = tester.getSemantics(
        find.byKey(const Key('quick_action_nuevo_alumno')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: '"+ Nuevo alumno" debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('quick_action_nuevo_alumno'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('page:/alumnos'), findsOneWidget,
          reason: 'Enter (teclado) debe activar el CTA igual que el tap');

      handle.dispose();
    });
  });
}
