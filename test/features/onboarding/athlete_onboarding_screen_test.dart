// Tour de bienvenida del alumno (issue #627, slice 1).
//
// Monta la pantalla dentro de un GoRouter mínimo para poder asertar la
// NAVEGACIÓN real de cada salida, no sólo que el callback corrió. El foco está
// en las tres salidas (saltar, terminar, CTA de rankings) y en que la de
// "el write falló" siga siendo una salida — la lección de #429.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/application/onboarding_providers.dart';
import 'package:treino/features/onboarding/data/onboarding_repository.dart';
import 'package:treino/features/onboarding/domain/onboarding_seen.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/onboarding/presentation/athlete_onboarding_screen.dart';
import 'package:treino/features/onboarding/presentation/widgets/onboarding_page.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockOnboardingRepository extends Mock implements OnboardingRepository {}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _athlete() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// Router mínimo: el tour más los dos destinos a los que puede salir.
GoRouter _buildRouter() => GoRouter(
      initialLocation: '/onboarding/athlete',
      routes: [
        GoRoute(
          path: '/onboarding/athlete',
          builder: (_, __) => const AthleteOnboardingScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/feed',
          builder: (_, __) => const Scaffold(body: Text('FEED')),
        ),
      ],
    );

ProviderContainer _container(OnboardingRepository repo, UserProfile? profile) =>
    ProviderContainer(
      overrides: [
        onboardingRepositoryProvider.overrideWithValue(repo),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _athlete()),
        ),
      ],
    );

/// Usa [UncontrolledProviderScope] a propósito: así el test puede esperar el
/// primer snapshot del perfil ANTES de montar. En producción ese provider ya
/// está resuelto cuando el tour aparece (el gate del router necesitó leer el
/// perfil para llegar hasta acá), pero un `ProviderScope` lo inicializaría
/// recién en el primer `read` del controller, o sea en pleno tap.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required OnboardingRepository repo,
  UserProfile? profile,
}) async {
  final container = _container(repo, profile);
  addTearDown(container.dispose);
  await container.read(userProfileProvider.future);

  final router = _buildRouter();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// Avanza el PageView hasta la última página tocando el CTA principal.
Future<void> _goToLastPage(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byKey(const Key('onboarding_primary_button')));
    await tester.pumpAndSettle();
  }
}

void main() {
  late MockOnboardingRepository repo;

  setUpAll(() {
    registerFallbackValue(OnboardingSeen.empty);
    registerFallbackValue(OnboardingSurface.athleteMobile);
  });

  setUp(() {
    repo = MockOnboardingRepository();
    when(() => repo.markSeen(
          uid: any(named: 'uid'),
          current: any(named: 'current'),
          surface: any(named: 'surface'),
        )).thenAnswer(
      (_) async =>
          OnboardingSeen.empty.markSeen(OnboardingSurface.athleteMobile),
    );
  });

  testWidgets('arranca en la primera página con SALTAR ya visible',
      (tester) async {
    await _pump(tester, repo: repo);

    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    expect(find.text(l10n.onboardingAthleteTrainTitle), findsOneWidget);
    expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
    expect(find.text(l10n.onboardingStepLabel(1, 4)), findsOneWidget);
    // El CTA de la última página no debe estar visible todavía.
    expect(find.byKey(const Key('onboarding_rankings_cta')), findsNothing);
  });

  testWidgets('el CTA principal recorre las 4 páginas y termina en EMPEZAR',
      (tester) async {
    await _pump(tester, repo: repo);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    expect(find.text(l10n.onboardingNextCta), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_primary_button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.onboardingAthleteProgressTitle), findsOneWidget);
    expect(find.text(l10n.onboardingStepLabel(2, 4)), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_primary_button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.onboardingAthleteCoachTitle), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_primary_button')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.onboardingAthleteCommunityTitle), findsOneWidget);
    expect(find.text(l10n.onboardingFinishCta), findsOneWidget);
    expect(find.byKey(const Key('onboarding_rankings_cta')), findsOneWidget);
  });

  testWidgets('es swipeable: el gesto horizontal cambia de página',
      (tester) async {
    await _pump(tester, repo: repo);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    await tester.fling(
      find.byKey(const Key('onboarding_page_view')),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.onboardingAthleteProgressTitle), findsOneWidget);
  });

  testWidgets('SALTAR persiste el flag de athleteMobile y sale a /home',
      (tester) async {
    final router = await _pump(tester, repo: repo);

    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.markSeen(
          uid: captureAny(named: 'uid'),
          current: any(named: 'current'),
          surface: captureAny(named: 'surface'),
        )).captured;
    expect(captured[0], equals('athlete-uid'));
    expect(captured[1], equals(OnboardingSurface.athleteMobile));
    expect(_location(router), equals('/home'));
  });

  testWidgets('EMPEZAR en la última página persiste el flag y sale a /home',
      (tester) async {
    final router = await _pump(tester, repo: repo);
    await _goToLastPage(tester);

    await tester.tap(find.byKey(const Key('onboarding_primary_button')));
    await tester.pumpAndSettle();

    verify(() => repo.markSeen(
          uid: 'athlete-uid',
          current: any(named: 'current'),
          surface: OnboardingSurface.athleteMobile,
        )).called(1);
    expect(_location(router), equals('/home'));
  });

  testWidgets(
      'el CTA de rankings persiste el flag y aterriza en /feed?tab=rankings',
      (tester) async {
    final router = await _pump(tester, repo: repo);
    await _goToLastPage(tester);

    await tester.tap(find.byKey(const Key('onboarding_rankings_cta')));
    await tester.pumpAndSettle();

    verify(() => repo.markSeen(
          uid: 'athlete-uid',
          current: any(named: 'current'),
          surface: OnboardingSurface.athleteMobile,
        )).called(1);
    expect(_location(router), equals('/feed?tab=rankings'));
  });

  testWidgets(
      'si el write falla el usuario IGUAL sale, con aviso (#429 — nunca sin '
      'salida)', (tester) async {
    when(() => repo.markSeen(
          uid: any(named: 'uid'),
          current: any(named: 'current'),
          surface: any(named: 'surface'),
        )).thenThrow(Exception('permission-denied'));

    final router = await _pump(tester, repo: repo);
    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));

    await tester.tap(find.byKey(const Key('onboarding_skip_button')));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.onboardingSaveError), findsOneWidget);
    await tester.pumpAndSettle();
    expect(_location(router), equals('/home'));
  });

  testWidgets('salir baja el escape hatch de sesión del gate del router',
      (tester) async {
    // Sin este flag, el gate volvería a mandar al alumno al tour cuando el
    // write no llegó a persistirse.
    when(() => repo.markSeen(
          uid: any(named: 'uid'),
          current: any(named: 'current'),
          surface: any(named: 'surface'),
        )).thenThrow(Exception('offline'));

    final container = _container(repo, null);
    addTearDown(container.dispose);
    await container.read(userProfileProvider.future);

    expect(container.read(onboardingDismissedProvider), isFalse);
    expect(container.read(athleteOnboardingPendingProvider), isTrue);

    await container
        .read(onboardingControllerProvider)
        .markSeen(OnboardingSurface.athleteMobile);

    expect(container.read(onboardingDismissedProvider), isTrue);
  });

  testWidgets('reusa OnboardingPage — una página por paso', (tester) async {
    await _pump(tester, repo: repo);
    // El PageView mantiene montada sólo la página visible más las adyacentes
    // que ya construyó; alcanza con verificar que la primera es una
    // OnboardingPage y no un widget ad-hoc.
    expect(find.byType(OnboardingPage), findsWidgets);
  });
}
