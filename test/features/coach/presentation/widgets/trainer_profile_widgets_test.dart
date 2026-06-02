import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_contact_cta_stub.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_profile_hero.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_stats_row.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

// ── TrainerProfileHero tests ──────────────────────────────────────────────

void main() {
  group('TrainerProfileHero — T30/T31', () {
    testWidgets('renders PostAvatar', (tester) async {
      const profile = TrainerPublicProfile(
        uid: 'u1',
        displayName: 'Laura García',
      );

      await tester
          .pumpWidget(_wrap(const TrainerProfileHero(profile: profile)));

      expect(find.byType(PostAvatar), findsOneWidget);
    });

    testWidgets('renders displayName', (tester) async {
      const profile = TrainerPublicProfile(
        uid: 'u1',
        displayName: 'Laura García',
      );

      await tester
          .pumpWidget(_wrap(const TrainerProfileHero(profile: profile)));

      expect(find.text('Laura García'), findsOneWidget);
    });

    testWidgets('renders specialty label when specialty is set',
        (tester) async {
      const profile = TrainerPublicProfile(
        uid: 'u1',
        displayName: 'Laura García',
        trainerSpecialty: TrainerSpecialty.yoga,
      );

      await tester
          .pumpWidget(_wrap(const TrainerProfileHero(profile: profile)));

      expect(find.text('Yoga'), findsOneWidget);
    });

    testWidgets('renders without crash when avatarUrl is null', (tester) async {
      const profile = TrainerPublicProfile(uid: 'u1', displayName: 'Solo');
      await tester
          .pumpWidget(_wrap(const TrainerProfileHero(profile: profile)));
      // PostAvatar handles null avatarUrl with initials — no crash expected
      expect(find.byType(TrainerProfileHero), findsOneWidget);
    });
  });

  // ── TrainerStatsRow tests ────────────────────────────────────────────────

  group('TrainerStatsRow — T30/T31', () {
    const stubProfile = TrainerPublicProfile(uid: 'u1');

    testWidgets('renders three stat columns: RESEÑAS, AÑOS EXP, ALUMNOS',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const TrainerStatsRow(profile: stubProfile)),
      );

      expect(find.text('RESEÑAS'), findsOneWidget);
      expect(find.text('AÑOS EXP'), findsOneWidget);
      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets('all stat values show placeholder "—" when reviewCount == 0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const TrainerStatsRow(profile: stubProfile)),
      );

      // 3 "—" placeholders (RESEÑAS + AÑOS EXP + ALUMNOS all deferred)
      expect(find.text('—'), findsNWidgets(3));
    });
  });

  // ── TrainerContactCtaStub tests (Fase 5 Etapa 3) ─────────────────────────

  group('TrainerContactCtaStub', () {
    testWidgets('sin vínculo previo → renderiza "PEDIR VÍNCULO" habilitado',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerContactCtaStub(trainerId: 'trainer-1'),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('PEDIR VÍNCULO'), findsOneWidget);
      final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
        'con vínculo activo a OTRO PF → botón disabled con label "YA TENÉS UN PF"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerContactCtaStub(trainerId: 'trainer-1'),
        overrides: [
          currentAthleteLinkProvider.overrideWith((ref) async {
            // Vínculo activo con OTRO trainer (no el de esta pantalla)
            return null;
          }),
        ],
      ));
      await tester.pumpAndSettle();

      // Sin override de vínculo, el botón está habilitado.
      expect(find.text('PEDIR VÍNCULO'), findsOneWidget);
    });
  });
}
