import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer({TrainerSubscription? subscription}) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      subscription: subscription,
    );

Widget _harness({
  required List<TrainerLink> links,
  UserProfile? profile,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(links)),
      ],
      child: const MaterialApp(home: Scaffold(body: FacturacionTab())),
    );

TrainerLink _link(String athleteId, TrainerLinkStatus status) => TrainerLink(
      id: 'link_$athleteId',
      trainerId: 'pf1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime(2025, 1, 1),
    );

void main() {
  testWidgets('sin suscripción → Free, límite 2, uso 0', (tester) async {
    await tester.pumpWidget(_harness(links: const []));
    await tester.pump();

    expect(find.text('FACTURACIÓN TREINO'), findsOneWidget);
    expect(find.text('TREINO Coach · Free'), findsOneWidget);
    expect(find.text('0 / 2'), findsOneWidget);
    // CAMBIAR PLAN existe pero deshabilitado (pantalla es PR3).
    expect(find.text('CAMBIAR PLAN'), findsOneWidget);
    // Ya NO hay empty state ni historial de comprobantes (fuera de scope).
    expect(find.text('Facturación próximamente'), findsNothing);
    expect(find.text('HISTORIAL DE FACTURACIÓN'), findsNothing);
  });

  testWidgets('carga ponderada: 2 activos + 1 pausado = 2.5 / límite',
      (tester) async {
    await tester.pumpWidget(_harness(
      profile: _trainer(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.active,
          weightLimit: 7,
        ),
      ),
      links: [
        _link('a1', TrainerLinkStatus.active),
        _link('a2', TrainerLinkStatus.active),
        _link('a3', TrainerLinkStatus.paused),
      ],
    ));
    await tester.pump();

    expect(find.text('TREINO Coach · Plan 1'), findsOneWidget);
    // 2×1.0 + 1×0.5 = 2.5, límite del Plan 1 = 7.
    expect(find.text('2.5 / 7'), findsOneWidget);
  });

  testWidgets('entero se muestra sin decimal (3 activos → "3 / 7")',
      (tester) async {
    await tester.pumpWidget(_harness(
      profile: _trainer(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan1,
          status: SubscriptionStatus.active,
          weightLimit: 7,
        ),
      ),
      links: [
        _link('a1', TrainerLinkStatus.active),
        _link('a2', TrainerLinkStatus.active),
        _link('a3', TrainerLinkStatus.active),
      ],
    ));
    await tester.pump();

    expect(find.text('3 / 7'), findsOneWidget);
  });

  testWidgets('dedup por athleteId (activo duplicado cuenta 1)',
      (tester) async {
    await tester.pumpWidget(_harness(links: [
      _link('a1', TrainerLinkStatus.active),
      _link('a1', TrainerLinkStatus.active),
    ]));
    await tester.pump();

    // Free límite 2, un solo athlete distinto → 1 / 2.
    expect(find.text('1 / 2'), findsOneWidget);
  });
}
