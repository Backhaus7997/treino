import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_contact_cta_stub.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_profile_hero.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_stats_row.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
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
    testWidgets('renders three stat columns: RESEÑAS, AÑOS EXP, ALUMNOS',
        (tester) async {
      await tester.pumpWidget(_wrap(const TrainerStatsRow()));

      expect(find.text('RESEÑAS'), findsOneWidget);
      expect(find.text('AÑOS EXP'), findsOneWidget);
      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets('all stat values show placeholder "—"', (tester) async {
      await tester.pumpWidget(_wrap(const TrainerStatsRow()));

      // 3 "—" placeholders
      expect(find.text('—'), findsNWidgets(3));
    });
  });

  // ── TrainerContactCtaStub tests ──────────────────────────────────────────

  group('TrainerContactCtaStub — T30/T31', () {
    testWidgets('renders "PEDIR VÍNCULO" button', (tester) async {
      await tester.pumpWidget(_wrap(const TrainerContactCtaStub()));

      expect(find.text('PEDIR VÍNCULO'), findsOneWidget);
    });

    testWidgets('tapping shows SnackBar "Próximamente — Etapa 3"',
        (tester) async {
      await tester.pumpWidget(_wrap(const TrainerContactCtaStub()));

      await tester.tap(find.text('PEDIR VÍNCULO'));
      await tester.pump();

      expect(find.text('Próximamente — Etapa 3'), findsOneWidget);
    });
  });
}
