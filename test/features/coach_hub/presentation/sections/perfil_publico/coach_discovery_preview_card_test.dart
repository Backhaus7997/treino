// CoachDiscoveryPreviewCard — Fase 11 WU-02.
//
// Card "PREVIEW EN TREINO COACH DISCOVERY" (columna derecha del mockup) —
// data 100% real: identidad/bio/specialty/rate/online de `UserProfile`
// (pasado como prop) + rating/reseñas de `trainerByIdProvider` + conteo de
// alumnos activos de `trainerLinksStreamProvider`. Sin años/experiencia
// (no cableado, ADR-F11-01).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart'
    show trainerByIdProvider;
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/widgets/coach_discovery_preview_card.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

const _trainerUid = 'trainer-1';

UserProfile _profile({
  String? displayName = 'Joaquín Nadal',
  String? trainerSpecialty = 'hipertrofia',
  int? trainerMonthlyRate = 28000,
  bool trainerOffersOnline = true,
  List<TrainerLocation> trainerLocations = const [],
}) =>
    UserProfile(
      uid: _trainerUid,
      email: 'trainer@treino.app',
      displayName: displayName,
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      trainerSpecialty: trainerSpecialty,
      trainerMonthlyRate: trainerMonthlyRate,
      trainerOffersOnline: trainerOffersOnline,
      trainerLocations: trainerLocations,
    );

TrainerLink _activeLink(String id) => TrainerLink(
      id: id,
      trainerId: _trainerUid,
      athleteId: 'athlete-$id',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2025, 6, 1),
      acceptedAt: DateTime.utc(2025, 6, 2),
    );

Future<void> _pump(
  WidgetTester tester, {
  required UserProfile profile,
  TrainerPublicProfile? trainerPublicProfile,
  List<TrainerLink> links = const [],
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerByIdProvider(_trainerUid).overrideWith(
          (ref) async => trainerPublicProfile,
        ),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream<List<TrainerLink>>.value(links),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: Scaffold(body: CoachDiscoveryPreviewCard(profile: profile)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachDiscoveryPreviewCard — happy path (WU-02)', () {
    testWidgets('renderiza identidad, specialty, modalidad y tarifa reales',
        (tester) async {
      await _pump(
        tester,
        profile: _profile(
          trainerLocations: const [
            TrainerLocation(
              id: 'loc-1',
              type: TrainerLocationType.gym,
              gymId: 'gym-1',
              lat: -34.6037,
              lng: -58.3816,
              geohash: '6gy1qt',
            ),
          ],
        ),
        trainerPublicProfile: const TrainerPublicProfile(
          uid: _trainerUid,
          trainerSpecialty: TrainerSpecialty.hipertrofia,
          averageRating: 4.9,
          reviewCount: 8,
        ),
        links: [
          _activeLink('a1'),
          _activeLink('a2'),
          _activeLink('a3'),
          TrainerLink(
            id: 'p1',
            trainerId: _trainerUid,
            athleteId: 'athlete-p1',
            status: TrainerLinkStatus.paused,
            requestedAt: DateTime.utc(2025, 6, 1),
          ),
        ],
      );

      expect(find.text('Joaquín Nadal'), findsOneWidget);
      expect(
        find.textContaining('Personal Trainer'),
        findsOneWidget,
      );
      expect(find.textContaining('Hipertrofia'), findsWidgets);
      expect(find.textContaining('Online'), findsOneWidget);
      expect(find.textContaining('Presencial'), findsOneWidget);
      expect(find.text('\$28000/mes'), findsOneWidget);

      // Alumnos: solo cuenta los `active` (3), no el `paused`.
      expect(find.text('3'), findsOneWidget);

      // Rating + reseñas reales.
      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('reviewCount 0 → RATING y RESEÑAS muestran "—" (ADR-RV-011)',
        (tester) async {
      await _pump(
        tester,
        profile: _profile(),
        trainerPublicProfile: const TrainerPublicProfile(
          uid: _trainerUid,
          averageRating: null,
        ),
        links: const [],
      );

      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('CTA "Solicitar contacto" está deshabilitado (es preview)',
        (tester) async {
      await _pump(
        tester,
        profile: _profile(),
        trainerPublicProfile: const TrainerPublicProfile(uid: _trainerUid),
        links: const [],
      );

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Solicitar contacto'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('CoachDiscoveryPreviewCard — motion/tema (WU-02)', () {
    testWidgets('dark y light: smoke sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(
          tester,
          profile: _profile(),
          trainerPublicProfile: const TrainerPublicProfile(uid: _trainerUid),
          links: const [],
          theme: theme,
        );
        expect(find.text('Joaquín Nadal'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
