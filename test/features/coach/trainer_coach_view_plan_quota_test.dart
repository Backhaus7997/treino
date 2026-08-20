import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Medidor de cupo del roster móvil (artboard G): «2 DE 2 · PLAN FREE».
///
/// El valor del header es avisar ANTES del choque, así que lo que se testea es
/// el contrato del string: numerador ponderado, denominador solo cuando el tier
/// tiene tope, y estado visual distinto al llegar al límite.

const _headerKey = Key('plan-quota-header');

TrainerLink _link(
  String athleteId,
  TrainerLinkStatus status,
) =>
    TrainerLink(
      id: 'link-$athleteId',
      trainerId: 'pf1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

UserProfile _trainer(TrainerSubscription? subscription) => UserProfile(
      uid: 'pf1',
      email: 'pf@test.com',
      displayName: 'Profe',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      subscription: subscription,
    );

/// `weightLimit` se deja sin setear a propósito: el header debe resolver el
/// tope desde el TIER, no desde el denormalizado.
TrainerSubscription _sub(SubscriptionTier tier) => TrainerSubscription(
      tier: tier,
      status: SubscriptionStatus.active,
    );

Widget _harness({
  required List<TrainerLink> links,
  TrainerSubscription? subscription,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_trainer(subscription)),
        ),
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        for (final l in links) ...[
          userPublicProfileProvider(l.athleteId).overrideWith(
            (ref) => Stream.value(
              UserPublicProfile(
                uid: l.athleteId,
                displayName: 'Atleta ${l.athleteId}',
                displayNameLowercase: 'atleta ${l.athleteId}',
              ),
            ),
          ),
          hasUnreadFromProvider(l.athleteId).overrideWith((ref) => false),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: TrainerCoachView()),
      ),
    );

String _headerText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_headerKey)).data!;

Color _headerColor(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_headerKey)).style!.color!;

void main() {
  group('medidor de cupo — un tier, un denominador', () {
    testWidgets('Free: 2 activos → "2 DE 2 · PLAN FREE"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 2 · PLAN FREE');
    });

    testWidgets('Plan 1: 3 activos → "3 DE 7 · PLAN 1"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
          _link('a3', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '3 DE 7 · PLAN 1');
    });

    testWidgets('Plan 2: 1 activo → "1 DE 15 · PLAN 2"', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan2),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 15 · PLAN 2');
    });

    testWidgets(
        'sin suscripción en el doc → Free por definición (sin backfill)',
        (tester) async {
      await tester.pumpWidget(_harness(
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 2 · PLAN FREE');
    });
  });

  group('medidor de cupo — Plan 3 no tiene tope', () {
    testWidgets('Plan 3: sin denominador y SIN la palabra "null"',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      final text = _headerText(tester);
      expect(text, '2 ALUMNOS · PLAN 3');
      expect(text, isNot(contains('DE')));
      expect(text.toLowerCase(), isNot(contains('null')));
    });

    testWidgets(
        'Plan 3 con un weightLimit viejo denormalizado sigue sin denominador',
        (tester) async {
      // El CF puede haber dejado un `weightLimit: 15` de cuando el PF era
      // Plan 2. El tier manda: si el header leyera el denormalizado, el plan
      // ilimitado mostraría un tope que no existe.
      await tester.pumpWidget(_harness(
        subscription: const TrainerSubscription(
          tier: SubscriptionTier.plan3,
          status: SubscriptionStatus.active,
          weightLimit: 15,
        ),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 ALUMNO · PLAN 3');
    });

    testWidgets('ningún tier renderiza "null" en el header', (tester) async {
      for (final tier in SubscriptionTier.values) {
        await tester.pumpWidget(_harness(
          subscription: _sub(tier),
          links: [
            _link('a1', TrainerLinkStatus.active),
            _link('a2', TrainerLinkStatus.paused),
          ],
        ));
        await tester.pumpAndSettle();

        expect(
          _headerText(tester).toLowerCase(),
          isNot(contains('null')),
          reason: 'el tier $tier filtró un null al header',
        );
      }
    });
  });

  group('medidor de cupo — la carga es ponderada y fraccionaria', () {
    testWidgets('un pausado pesa 0.5 → "0.5", no "0.5.0" ni "1"',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [_link('a1', TrainerLinkStatus.paused)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '0.5 DE 2 · PLAN FREE');
    });

    testWidgets('activo + pausado = 1.5 (un decimal, no dos)', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1.5 DE 7 · PLAN 1');
    });

    testWidgets('entero no arrastra decimal ("2", no "2.0")', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan1),
        links: [
          _link('a1', TrainerLinkStatus.paused),
          _link('a2', TrainerLinkStatus.paused),
          _link('a3', TrainerLinkStatus.paused),
          _link('a4', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 7 · PLAN 1');
    });

    testWidgets('sin tope: 1 exacto va en singular, 0.5 en plural',
        (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [_link('a1', TrainerLinkStatus.paused)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '0.5 ALUMNOS · PLAN 3');
    });
  });

  group('medidor de cupo — estado visual al límite', () {
    testWidgets('bajo el límite queda en textMuted', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [_link('a1', TrainerLinkStatus.active)],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '1 DE 2 · PLAN FREE');
      expect(_headerColor(tester), palette.textMuted);
    });

    testWidgets('al límite (load == limit) cambia a highlight', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2 DE 2 · PLAN FREE');
      expect(
        _headerColor(tester),
        palette.highlight,
        reason: 'al llegar al tope el PF tiene que VERLO, no leerlo',
      );
      expect(
        palette.highlight,
        isNot(palette.textMuted),
        reason:
            'si los dos tokens coincidieran, el estado no distinguiría nada',
      );
    });

    testWidgets('por encima del límite también queda en highlight',
        (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: [
          _link('a1', TrainerLinkStatus.active),
          _link('a2', TrainerLinkStatus.active),
          _link('a3', TrainerLinkStatus.paused),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '2.5 DE 2 · PLAN FREE');
      expect(_headerColor(tester), palette.highlight);
    });

    testWidgets('Plan 3 nunca entra en el estado de límite', (tester) async {
      final palette = AppTheme.dark().extension<AppPalette>()!;

      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.plan3),
        links: [
          for (var i = 0; i < 20; i++) _link('a$i', TrainerLinkStatus.active),
        ],
      ));
      await tester.pumpAndSettle();

      expect(_headerText(tester), '20 ALUMNOS · PLAN 3');
      expect(_headerColor(tester), palette.textMuted);
    });
  });

  group('medidor de cupo — presencia', () {
    testWidgets('se muestra también con el roster vacío', (tester) async {
      await tester.pumpWidget(_harness(
        subscription: _sub(SubscriptionTier.free),
        links: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin alumnos activos todavía.'), findsOneWidget);
      expect(_headerText(tester), '0 DE 2 · PLAN FREE');
    });
  });
}
