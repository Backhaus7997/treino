// #1503: la card «ASIGNAR A UN ALUMNO» decía «La plantilla queda guardada y
// la podés reutilizar», pero asignar un plan NO guarda ninguna plantilla (la
// biblioteca seguía en «0 de 3»). Un copy que afirma algo falso — AGENTS §11.1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';
import 'package:treino/l10n/app_l10n.dart';

void main() {
  testWidgets('la card de asignar no promete guardar una plantilla',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('pf'),
        trainerTemplatesStreamProvider('pf')
            .overrideWith((ref) => Stream.value(const <Routine>[])),
        templateQuotaProvider
            .overrideWith((ref) => const AsyncValue.data((limit: 3, count: 0))),
        userPublicProfileProvider('pf')
            .overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerWorkoutView()),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('queda guardada'), findsNothing,
        reason: 'asignar un plan no guarda ninguna plantilla');
    // Y dice cómo se reutiliza de verdad: armándolo como plantilla.
    expect(find.textContaining('armalo como plantilla'), findsOneWidget);
  });
}
