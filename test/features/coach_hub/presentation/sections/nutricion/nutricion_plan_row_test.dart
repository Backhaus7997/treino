// Tests de NutricionPlanRow — fila presentational del overview de
// Nutrición (WU-03, Fase 6). Sigue el patrón de
// `friend_request_inbox_tile_test.dart`: ProviderScope con override directo
// de `userPublicProfileProvider` (el widget lo watchea internamente).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/widgets/nutricion_plan_row.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

TrainerLink _link({String athleteId = 'athlete-1'}) => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
    );

NutritionPlan _plan({int meals = 3, DateTime? updatedAt}) => NutritionPlan(
      id: 'plan-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      title: 'Plan',
      meals: List.generate(
        meals,
        (i) => Meal(id: 'meal-$i', name: 'Comida $i', groups: const []),
      ),
      updatedAt: updatedAt ?? DateTime.now(),
    );

Widget _buildRow({
  required NutricionEntry entry,
  VoidCallback? onTap,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      userPublicProfileProvider(entry.link.athleteId).overrideWith(
        (_) => Stream.value(
          const UserPublicProfile(uid: 'athlete-1', displayName: 'Ana García'),
        ),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: NutricionPlanRow(entry: entry, onTap: onTap),
      ),
    ),
  );
}

void main() {
  testWidgets('con plan muestra la cantidad de comidas', (tester) async {
    final entry = (
      link: _link(),
      plan: _plan(meals: 4),
      planLoading: false,
    );

    await tester.pumpWidget(_buildRow(entry: entry));
    await tester.pump();

    expect(find.textContaining('4 comidas'), findsOneWidget);
    expect(find.text('Ana García'), findsOneWidget);
  });

  testWidgets('sin plan muestra "Sin plan todavía"', (tester) async {
    final entry = (
      link: _link(),
      plan: null,
      planLoading: false,
    );

    await tester.pumpWidget(_buildRow(entry: entry));
    await tester.pump();

    expect(find.text('Sin plan todavía'), findsOneWidget);
  });

  testWidgets('planLoading muestra shimmer (skeleton del list row)',
      (tester) async {
    final entry = (
      link: _link(),
      plan: null,
      planLoading: true,
    );

    await tester.pumpWidget(_buildRow(entry: entry));
    await tester.pump();

    expect(find.byKey(const Key('list_row_skeleton')), findsOneWidget);
    expect(find.text('Sin plan todavía'), findsNothing);
  });

  testWidgets(
      'NutricionPlanRow.loading muestra shimmer sin necesitar un entry '
      '(WU-05, roster completo en loading)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const Scaffold(body: NutricionPlanRow.loading()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('list_row_skeleton')), findsOneWidget);
  });

  testWidgets('onTap dispara el callback inyectado', (tester) async {
    var tapped = false;
    final entry = (
      link: _link(),
      plan: _plan(meals: 2),
      planLoading: false,
    );

    await tester.pumpWidget(
      _buildRow(entry: entry, onTap: () => tapped = true),
    );
    await tester.pump();

    await tester.tap(find.text('Ana García'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
