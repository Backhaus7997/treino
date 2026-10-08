// La franja "Tu rango" de las pestañas de levantamientos: qué estado muestra
// según lo que sabemos del atleta, y a dónde lleva cuando falta el peso corporal.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gym_rankings/domain/lift_rank.dart';
import 'package:treino/features/gym_rankings/domain/ranking_dimension.dart';
import 'package:treino/features/gym_rankings/presentation/widgets/lift_rank_strip.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'me';

UserProfile _private({double? bodyWeightKg}) => UserProfile(
      uid: _uid,
      email: 'me@treino.app',
      displayName: 'Yo',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      bodyWeightKg: bodyWeightKg,
    );

Widget _host({
  required UserPublicProfile publicProfile,
  double? bodyWeightKg,
  RankingDimension dimension = RankingDimension.bench,
  String liftLabel = 'BANCA',
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: LiftRankStrip(
              myUid: _uid,
              dimension: dimension,
              liftLabel: liftLabel,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/edit-personal',
        builder: (_, __) => const Scaffold(
          body: Text('edit', key: Key('edit_personal_destination')),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      userPublicProfileProvider(_uid)
          .overrideWith((_) => Stream.value(publicProfile)),
      userProfileProvider.overrideWith(
        (_) => Stream.value(_private(bodyWeightKg: bodyWeightKg)),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: router,
    ),
  );
}

/// Bombea hasta que la franja resolvió sus providers y, con ellos, el SVG.
Future<void> _pump(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('liftRankStripState — la decisión, sin pintar nada', () {
    test('con rango de Bronce para arriba: ranked', () {
      expect(
        liftRankStripState(rank: LiftRank.gold, bestKg: 90, bodyWeightKg: 80),
        LiftRankStripState.ranked,
      );
    });

    test('con rango 0: belowFirstRank', () {
      expect(
        liftRankStripState(rank: LiftRank.none, bestKg: 20, bodyWeightKg: 80),
        LiftRankStripState.belowFirstRank,
      );
    });

    test('sin levantamiento: noLift, aunque falte el peso', () {
      expect(
        liftRankStripState(rank: null, bestKg: null, bodyWeightKg: null),
        LiftRankStripState.noLift,
      );
      expect(
        liftRankStripState(rank: null, bestKg: null, bodyWeightKg: 80),
        LiftRankStripState.noLift,
      );
    });

    test('con levantamiento pero sin peso corporal: noBodyWeight', () {
      expect(
        liftRankStripState(rank: null, bestKg: 90, bodyWeightKg: null),
        LiftRankStripState.noBodyWeight,
      );
    });

    test(
        'con levantamiento y peso, y sin rango: pending (no es culpa del atleta)',
        () {
      expect(
        liftRankStripState(rank: null, bestKg: 90, bodyWeightKg: 80),
        LiftRankStripState.pending,
      );
    });
  });

  test('"de 8" es la cantidad de rangos con insignia', () {
    expect(kLiftRankTotal, LiftRank.values.length - 1);
  });

  group('LiftRankStrip', () {
    testWidgets('con rango: nombre, "Rango n de 8" y la insignia',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(
            uid: _uid,
            bestBenchKg: 90,
            benchRank: 3,
          ),
          bodyWeightKg: 80,
        ),
      );

      expect(find.text('TU RANGO · BANCA'), findsOneWidget);
      expect(_text(tester, 'rankings_my_rank_name'), 'ORO');
      expect(_text(tester, 'rankings_my_rank_hint'), 'Rango 3 de 8');
      expect(find.byKey(const Key('rankings_my_rank_badge')), findsOneWidget);
    });

    testWidgets('lee el rango del levantamiento de la pestaña, no otro',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(
            uid: _uid,
            bestSquatKg: 150,
            squatRank: 5,
            bestBenchKg: 60,
            benchRank: 1,
          ),
          bodyWeightKg: 80,
          dimension: RankingDimension.squat,
          liftLabel: 'SENTADILLA',
        ),
      );

      expect(find.text('TU RANGO · SENTADILLA'), findsOneWidget);
      expect(_text(tester, 'rankings_my_rank_name'), 'DIAMANTE');
      expect(_text(tester, 'rankings_my_rank_hint'), 'Rango 5 de 8');
    });

    testWidgets('con rango 0: "Sin rango" y cuánto falta, sin número de rango',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(
            uid: _uid,
            bestBenchKg: 20,
            benchRank: 0,
          ),
          bodyWeightKg: 80,
        ),
      );

      expect(_text(tester, 'rankings_my_rank_name'), 'SIN RANGO');
      expect(_text(tester, 'rankings_my_rank_hint'),
          'Todavía no llegás a Bronce. Seguí sumando kilos.');
    });

    testWidgets('sin levantamiento registrado: lo pide, sin nombre de rango',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(uid: _uid),
          bodyWeightKg: 80,
        ),
      );

      expect(find.byKey(const Key('rankings_my_rank_name')), findsNothing);
      expect(_text(tester, 'rankings_my_rank_hint'),
          'Registrá este levantamiento en un entrenamiento para ver tu rango.');
    });

    testWidgets('sin peso corporal: toda la franja lleva a cargarlo',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(uid: _uid, bestBenchKg: 90),
        ),
      );

      expect(_text(tester, 'rankings_my_rank_hint'),
          'Cargá tu peso corporal para ver tu rango.');
      expect(find.byKey(const Key('rankings_my_rank_name')), findsNothing);

      await tester.tap(find.byKey(const Key('rankings_my_rank_strip')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('edit_personal_destination')), findsOneWidget);
    });

    testWidgets(
        'con peso y levantamiento pero sin rango: espera al recompute y no manda a cargar nada',
        (tester) async {
      await _pump(
        tester,
        _host(
          publicProfile: const UserPublicProfile(uid: _uid, bestBenchKg: 90),
          bodyWeightKg: 80,
        ),
      );

      expect(_text(tester, 'rankings_my_rank_hint'),
          'Se calcula con tu próximo entrenamiento.');

      // Ya cargó su peso: tocar la franja no lo manda a ningún lado.
      await tester.tap(find.byKey(const Key('rankings_my_rank_strip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit_personal_destination')), findsNothing);
    });
  });
}
