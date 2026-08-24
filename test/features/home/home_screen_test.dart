import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/home/widgets/empezar_entrenamiento_card.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';
import 'package:treino/features/home/widgets/home_header.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/l10n/app_l10n.dart';

UserProfile makeProfile({
  String? displayName = 'Martín',
  String? avatarUrl,
  String uid = 'u1',
  String email = 'u1@test.com',
}) =>
    UserProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
      avatarUrl: avatarUrl,
    );

Session makeStubSession({DateTime? startedAt}) => Session(
      id: 'stub-session-001',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: startedAt ?? DateTime.utc(2026, 5, 18, 18, 42),
      status: SessionStatus.active,
      dayNumber: 1,
    );

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: w),
      ),
    );

// ─── First-run harness (#636) ────────────────────────────────────────────────

const _uid = 'u1';

Routine _routine({String id = 'r1'}) => Routine(
      id: id,
      name: 'Full body',
      level: ExperienceLevel.beginner,
      // `days` vacío es válido (SCENARIO-052) y alcanza: estos tests sólo
      // miran si la lista de rutinas está vacía o no, nunca su contenido.
      days: const [],
    );

/// Overrides que ponen a Home en el estado que renderiza
/// `_AthleteFirstRunCard`: uid resuelto y AMBAS listas de rutinas resueltas a
/// vacío. Los providers Firestore que cuelgan del uid se cortan acá — con uid
/// real irían a la red y el test dejaría de ser hermético.
List<Override> _firstRunOverrides({
  List<Routine> created = const [],
  List<Routine> assigned = const [],
}) =>
    [
      userProfileProvider.overrideWith((ref) => Stream.value(makeProfile())),
      currentUidProvider.overrideWithValue(_uid),
      userCreatedRoutinesProvider(_uid).overrideWith(
        (ref) => Stream.value(created),
      ),
      assignedRoutinesProvider(_uid).overrideWith((ref) async => assigned),
      activeSessionForUidProvider.overrideWith((ref) async => null),
      todaysRoutineProvider.overrideWith((ref) async => null),
      weeklyInsightsProvider.overrideWith((ref) async => null),
    ];

/// Home montada dentro de un GoRouter real, con rutas señuelo para cada
/// destino de los tres caminos. Verificar el destino por la pantalla que
/// aparece —y no espiando un callback— es lo único que prueba que la URL que
/// se pushea de verdad resuelve.
Widget _wrapWithRouter(GoRouter router, List<Override> overrides) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    );

GoRouter _firstRunRouter() => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: HomeScreen()),
        ),
        GoRoute(
          path: '/workout',
          builder: (_, state) => Scaffold(
            body: Text('WORKOUT:${state.uri.queryParameters['tab']}'),
          ),
        ),
        GoRoute(
          path: '/workout/my-routine-editor',
          builder: (_, __) => const Scaffold(body: Text('EDITOR')),
        ),
        GoRoute(
          path: '/coach',
          builder: (_, __) => const Scaffold(body: Text('COACH')),
        ),
      ],
    );

void main() {
  group('HomeScreen', () {
    testWidgets(
        'REQ-HOME-SCREEN-001: AsyncData(profile) → HomeHeader, EmpezarEntrenamientoCard, EstaSemanaCard each found once',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SCREEN-001 / REQ-HOME-PROVIDER-003: AsyncLoading → no HomeHeader, skeleton present, cards still visible',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => const Stream<UserProfile?>.empty(),
          ),
        ],
      ));
      // Single pump — do NOT settle so the provider stays in AsyncLoading
      await tester.pump();

      expect(find.byType(HomeHeader), findsNothing);
      // Skeleton is a SizedBox(height: 56)
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && (w.height ?? 0) > 0,
        ),
        findsAtLeastNWidgets(1),
      );
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-SCREEN-001 / REQ-HOME-PROVIDER-004: AsyncError → no FlutterError, "HOLA!" shown, no error text',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.error(Exception('network')),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('HOLA!'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'[Ee]rror|[Ee]xcepci')),
        findsNothing,
      );
    });

    testWidgets(
        'REQ-HOME-SCREEN-002: no Scaffold/AppBackground/SafeArea inside HomeScreen',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Exactly 1 Scaffold — the outer test wrapper's
      expect(find.byType(Scaffold), findsOneWidget);
      // Zero AppBackground inside HomeScreen's subtree
      expect(find.byType(AppBackground), findsNothing);
      // Zero SafeArea
      expect(find.byType(SafeArea), findsNothing);
    });

    testWidgets(
        'REQ-HOME-SCREEN-003: AsyncData(profile) → HomeHeader.profile equals overridden profile',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final header = tester.widget<HomeHeader>(find.byType(HomeHeader));
      expect(header.profile, equals(profile));
    });

    testWidgets(
        'REQ-HOME-SCREEN-003: AsyncData(null) → HomeHeader.profile is null + "HOLA!" + no CachedNetworkImage',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      final header = tester.widget<HomeHeader>(find.byType(HomeHeader));
      expect(header.profile, isNull);
      expect(find.text('HOLA!'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets(
        'REQ-HOME-PROVIDER-001: AsyncData with displayName+avatarUrl → correct greeting + CachedNetworkImage',
        (tester) async {
      final profile = makeProfile(
        displayName: 'Martín',
        avatarUrl: 'https://example.com/avatar.jpg',
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('HOLA, MARTÍN!'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsAtLeastNWidgets(1));
    });

    // ── Resume listener (REQ-SESSION-RESUME-002) ─────────────────────────────

    testWidgets(
        'SCENARIO-325: activeSessionForUidProvider returns non-null → ResumeSessionModal aparece',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith(
            (ref) async => (session: makeStubSession(), setLogs: <SetLog>[]),
          ),
        ],
      ));
      // Initial pump + extra pumps to let the FutureProvider resolve and
      // the post-frame callback fire.
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-326: activeSessionForUidProvider returns null → sin modal, Home normal',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-327: activeSessionForUidProvider AsyncLoading → Home renderiza sin modal',
        (tester) async {
      final profile = makeProfile();
      // Override with a Future that never completes during this pump.
      final completer = Completer<({Session session, List<SetLog> setLogs})?>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(null);
      });
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith((ref) => completer.future),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-328: activeSessionForUidProvider AsyncError → Home renderiza sin modal',
        (tester) async {
      final profile = makeProfile();
      await tester.pumpWidget(_wrapWithOverrides(
        const HomeScreen(),
        [
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          activeSessionForUidProvider.overrideWith(
            (ref) => Future.error(Exception('network')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Entrenamiento en curso'), findsNothing);
      expect(find.byType(HomeHeader), findsOneWidget);
    });
  });

  // ─── #636: los TRES caminos del primer arranque ────────────────────────────

  group('HomeScreen — primer arranque del atleta (#636)', () {
    testWidgets(
        'sin rutinas → los tres CTAs visibles: crear rutina, explorar planes, buscar entrenador',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      expect(find.text('CREAR RUTINA'), findsOneWidget);
      expect(find.text('Explorar planes'), findsOneWidget);
      expect(find.text('Buscar entrenador'), findsOneWidget);
      // La card de "ya tenés rutina" NO puede convivir con la de arranque.
      expect(find.byType(EmpezarEntrenamientoCard), findsNothing);
    });

    testWidgets(
        'el body nombra los TRES caminos, no dos — y en el orden de los botones',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      // El copy viejo enumeraba dos caminos y le decía al atleta, con razón,
      // que sus opciones eran dos. Ese texto no puede volver.
      expect(
        find.text('Creá tu primera rutina o buscá un entrenador para empezar.'),
        findsNothing,
      );
      expect(
        find.text(
          'Creá tu propia rutina, explorá planes ya armados o buscá un '
          'entrenador que te guíe.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'tap en "Explorar planes" → /workout?tab=plantillas (el deep-link, NO el label)',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explorar planes'));
      await tester.pumpAndSettle();

      // `plantillas` y no `explorar`: el copy del tab cambió en #638, la ruta
      // no. Si alguien "sincroniza" el valor, rompe bookmarks vivos y este
      // test se pone rojo.
      expect(find.text('WORKOUT:plantillas'), findsOneWidget);
    });

    testWidgets('tap en "CREAR RUTINA" → /workout/my-routine-editor',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('CREAR RUTINA'));
      await tester.pumpAndSettle();

      expect(find.text('EDITOR'), findsOneWidget);
    });

    testWidgets('tap en "Buscar entrenador" → /coach', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buscar entrenador'));
      await tester.pumpAndSettle();

      expect(find.text('COACH'), findsOneWidget);
    });

    testWidgets(
        'con rutina propia → EmpezarEntrenamientoCard, y NINGUNO de los tres caminos (regresión #551)',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          _firstRunRouter(),
          _firstRunOverrides(created: [_routine()]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.text('CREAR RUTINA'), findsNothing);
      expect(find.text('Explorar planes'), findsNothing);
      expect(find.text('Buscar entrenador'), findsNothing);
    });

    testWidgets(
        'con plan asignado por un PF → EmpezarEntrenamientoCard, sin los tres caminos',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(
          _firstRunRouter(),
          _firstRunOverrides(assigned: [_routine(id: 'assigned-1')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmpezarEntrenamientoCard), findsOneWidget);
      expect(find.text('Explorar planes'), findsNothing);
    });

    testWidgets(
        'en pantalla chica (360x640) el tercer CTA no empuja EstaSemanaCard fuera del fold',
        (tester) async {
      // El issue pedía MEDIRLO, no darlo por bueno: tres pills apiladas de 48
      // suman ~58px a la card. Pixel-5-ish, el piso realista de la base.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrapWithRouter(_firstRunRouter(), _firstRunOverrides()),
      );
      await tester.pumpAndSettle();

      // El shell corre con extendBody: la barra flotante tapa el último tramo
      // del viewport, así que el fold útil termina antes de los 640.
      const fold = 640.0 - TreinoBottomBar.minHeight;
      final top = tester.getTopLeft(find.byType(EstaSemanaCard)).dy;

      expect(
        top,
        lessThan(fold),
        reason: 'EstaSemanaCard arranca en $top, debajo del fold útil ($fold): '
            'la card de primer arranque creció de más.',
      );
    });
  });
}
