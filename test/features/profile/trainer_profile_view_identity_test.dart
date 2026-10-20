// QA 2026-10-16 (#1497, #1501): la tarjeta de identidad y el menú del perfil del
// PF mentían de tres formas.
//
//  1. «Coach · Plan Pro» era un literal: un PF en Free leía que tenía Pro.
//     Ahora sale de `limiteDeAlumnosProvider`, la misma fuente del medidor
//     «2 DE 2 · PLAN FREE» de la pestaña Coach.
//  2. «— RATING» era un guion permanente aunque `averageRating` / `reviewCount`
//     existen. Ahora muestra el promedio real, y sin reseñas no se dibuja.
//  3. «Solicitudes entrantes» hacía `go('/home')`, donde ya no hay solicitudes
//     (viven en Notificaciones → «Solicitudes»).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/limite_de_alumnos_provider.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/notifications/application/notification_router.dart'
    show locationActualDe;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/trainer_profile_view.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-uid';
const _planKey = Key('trainer-profile-plan');

UserProfile _trainerProfile() => UserProfile(
      uid: _uid,
      email: 'pf@test.com',
      displayName: 'Coach Ana',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

TrainerLink _link(String id, TrainerLinkStatus status) => TrainerLink(
      id: id,
      trainerId: _uid,
      athleteId: 'athlete-$id',
      status: status,
      requestedAt: DateTime(2026, 1, 1),
    );

TrainerPublicProfile _public({double? averageRating, int reviewCount = 0}) =>
    TrainerPublicProfile(
      uid: _uid,
      displayName: 'Coach Ana',
      averageRating: averageRating,
      reviewCount: reviewCount,
    );

/// [limite] reemplaza al provider del plan; sin él, corre el real contra
/// [firestore] (o contra nada, y entonces cae al cálculo del cliente).
Widget _harness({
  TrainerPublicProfile? pub,
  List<TrainerLink> links = const [],
  LimiteDeAlumnos? limite,
  FakeFirebaseFirestore? firestore,
  GoRouter? router,
}) {
  final overrides = <Override>[
    currentUidProvider.overrideWithValue(_uid),
    userProfileProvider.overrideWith((_) => Stream.value(_trainerProfile())),
    trainerLinksStreamProvider.overrideWith((_) => Stream.value(links)),
    trainerByIdProvider(_uid).overrideWith((_) async => pub),
    if (limite != null) limiteDeAlumnosProvider.overrideWithValue(limite),
    if (firestore != null) firestoreProvider.overrideWithValue(firestore),
  ];
  const home = Scaffold(body: TrainerProfileView());
  final theme = AppTheme.dark();
  return ProviderScope(
    overrides: overrides,
    child: router == null
        ? MaterialApp(
            theme: theme,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: home,
          )
        : MaterialApp.router(
            theme: theme,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
  );
}

String _planText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_planKey)).data!;

void main() {
  group('plan bajo el nombre (#1497)', () {
    testWidgets('Free → «Coach · Plan Free», nunca «Plan Pro»', (tester) async {
      await tester.pumpWidget(_harness(
        limite: (tope: 2, tier: SubscriptionTier.free),
      ));
      await tester.pumpAndSettle();

      expect(_planText(tester), 'Coach · Plan Free');
      expect(find.textContaining('Pro'), findsNothing);
    });

    testWidgets('Plan 2 → «Coach · Plan 2»', (tester) async {
      await tester.pumpWidget(_harness(
        limite: (tope: 15, tier: SubscriptionTier.plan2),
      ));
      await tester.pumpAndSettle();

      expect(_planText(tester), 'Coach · Plan 2');
    });

    testWidgets('un tope que ningún plan tiene → «Coach» sin plan inventado',
        (tester) async {
      await tester.pumpWidget(_harness(limite: (tope: 9, tier: null)));
      await tester.pumpAndSettle();

      expect(_planText(tester), 'Coach');
    });

    testWidgets(
        'con el tope publicado por el servidor (athletes: 2) dice lo mismo '
        'que el medidor de Coach: Plan Free', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(_uid).set({
        'uid': _uid,
        'planLimits': {'athletes': 2},
      });

      await tester.pumpWidget(_harness(firestore: firestore));
      await tester.pumpAndSettle();

      expect(_planText(tester), 'Coach · Plan Free');
    });
  });

  group('RATING (#1497)', () {
    testWidgets('sin reseñas el stat no se dibuja (ni «—» ni un número)',
        (tester) async {
      await tester.pumpWidget(_harness(pub: _public()));
      await tester.pumpAndSettle();

      expect(find.text('ALUMNOS'), findsOneWidget);
      expect(find.text('RATING'), findsNothing);
    });

    testWidgets('perfil público sin crear → tampoco hay RATING',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.text('RATING'), findsNothing);
    });

    testWidgets('con reseñas muestra el promedio real a 1 decimal',
        (tester) async {
      await tester.pumpWidget(_harness(
        pub: _public(averageRating: 4.46, reviewCount: 12),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RATING'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
    });

    testWidgets('reseñas pero promedio todavía null → no inventa un número',
        (tester) async {
      await tester.pumpWidget(_harness(pub: _public(reviewCount: 3)));
      await tester.pumpAndSettle();

      expect(find.text('RATING'), findsNothing);
    });
  });

  testWidgets('«Disponibilidad» ya no usa el ícono de campana (#1497)',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Disponibilidad'),
      matching: find.byType(Row),
    );
    final icons = find
        .descendant(of: row.first, matching: find.byType(Icon))
        .evaluate()
        .map((e) => (e.widget as Icon).icon)
        .toList();

    expect(icons, contains(TreinoIcon.clock));
    expect(icons, isNot(contains(TreinoIcon.bell)));
  });

  group('«Solicitudes entrantes» (#1501)', () {
    GoRouter buildRouter() => GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: TrainerProfileView()),
            ),
            GoRoute(
              path: '/home',
              builder: (_, __) => const Scaffold(body: Text('INICIO')),
              routes: [
                GoRoute(
                  path: 'notifications',
                  builder: (_, state) => Scaffold(
                    body:
                        Text('NOTIFS tab=${state.uri.queryParameters['tab']}'),
                  ),
                ),
              ],
            ),
          ],
        );

    testWidgets(
        'abre Notificaciones en la pestaña «Solicitudes», no INICIO, y se '
        'puede volver al perfil', (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(_harness(
        router: router,
        links: [_link('p1', TrainerLinkStatus.pending)],
      ));
      await tester.pumpAndSettle();

      // El badge promete una solicitud pendiente.
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Solicitudes entrantes'));
      await tester.pumpAndSettle();

      // `currentConfiguration.uri` se queda en la base tras un `push`;
      // `state.uri` (vía `locationActualDe`) sí ve la ruta empujada.
      expect(locationActualDe(router), '/home/notifications?tab=solicitudes');
      expect(find.text('NOTIFS tab=solicitudes'), findsOneWidget);
      expect(find.text('INICIO'), findsNothing);

      // `push`, no `go`: la pantalla de Notificaciones vuelve con `pop()`.
      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(TrainerProfileView), findsOneWidget);
    });
  });
}
