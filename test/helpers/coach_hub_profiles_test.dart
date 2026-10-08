import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/domain/hub_onboarding_stage.dart';
import 'package:treino/features/profile/domain/user_profile_trainer_completeness.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import 'coach_hub_profiles.dart';

/// Reloj fijo: el predicado es puro y `now` entra por parámetro.
final DateTime _now = DateTime.utc(2026, 10, 5, 12);

void main() {
  group('fixtures de perfil del Hub', () {
    test('SCENARIO-050 trainerCompleto() esta en done y completo', () {
      final p = trainerCompleto();
      expect(p.role, UserRole.trainer);
      expect(hubOnboardingStage(p, now: _now), HubOnboardingStage.done);
      expect(p.trainerProfileComplete, isTrue);
    });

    test('trainerCompleto() acepta los overrides de identidad de cada suite',
        () {
      final p = trainerCompleto(
        uid: 'pf-1',
        email: 'pf@example.com',
        displayName: 'Mateo',
        onboardingSeen: const <String, int>{'x': 1},
      );
      expect(p.uid, 'pf-1');
      expect(p.email, 'pf@example.com');
      expect(p.displayName, 'Mateo');
      expect(p.onboardingSeen, const <String, int>{'x': 1});
      expect(hubOnboardingStage(p, now: _now), HubOnboardingStage.done);
    });

    test('trainerCompleto() tiene bornAt lejos del borde de los 13 anios', () {
      final p = trainerCompleto();
      expect(p.bornAt, DateTime.utc(1990, 1, 1));
      expect(p.bornAt!.isUtc, isTrue);
    });

    test('SCENARIO-049 trainerRecienPromovido() empieza en age', () {
      final p = trainerRecienPromovido();
      expect(p.role, UserRole.trainer);
      expect(p.bornAt, isNull);
      expect(hubOnboardingStage(p, now: _now), HubOnboardingStage.age);
    });
  });
}
