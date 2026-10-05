import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/domain/hub_onboarding_stage.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_profile_trainer_completeness.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Reloj fijo: el predicado es puro y `now` entra por parámetro.
final DateTime _now = DateTime(2026, 10, 5, 12);

UserProfile _trainer({
  String? displayName = 'ana_pf',
  DateTime? bornAt,
  bool completo = true,
  String? firstName,
  String? lastName,
  DateTime? termsAcceptedAt,
}) {
  return UserProfile(
    uid: 'u1',
    email: 'ana@example.com',
    displayName: displayName,
    role: UserRole.trainer,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    firstName: firstName,
    lastName: lastName,
    bornAt: bornAt,
    termsAcceptedAt: termsAcceptedAt,
    trainerBio:
        completo ? 'Entreno fuerza e hipertrofia hace diez años.' : null,
    trainerSpecialty: completo ? 'strength' : null,
    trainerMonthlyRate: completo ? 20000 : null,
    trainerOffersOnline: completo,
  );
}

final DateTime _bornAdulto = DateTime.utc(1990, 1, 1);

void main() {
  group('hubOnboardingStage', () {
    test('SCENARIO-001 orden age -> identity -> pf -> done', () {
      expect(
        hubOnboardingStage(
          _trainer(displayName: null, completo: false),
          now: _now,
        ),
        HubOnboardingStage.age,
      );
      expect(
        hubOnboardingStage(
          _trainer(displayName: null, completo: false, bornAt: _bornAdulto),
          now: _now,
        ),
        HubOnboardingStage.identity,
      );
      expect(
        hubOnboardingStage(
          _trainer(completo: false, bornAt: _bornAdulto),
          now: _now,
        ),
        HubOnboardingStage.pf,
      );
      expect(
        hubOnboardingStage(_trainer(bornAt: _bornAdulto), now: _now),
        HubOnboardingStage.done,
      );
    });

    test('SCENARIO-002 la edad va antes que la identidad', () {
      expect(
        hubOnboardingStage(_trainer(displayName: null), now: _now),
        HubOnboardingStage.age,
      );
      // Menor de 13 con displayName ausente: sigue siendo age.
      expect(
        hubOnboardingStage(
          _trainer(displayName: null, bornAt: DateTime.utc(2020, 1, 1)),
          now: _now,
        ),
        HubOnboardingStage.age,
      );
    });

    test('SCENARIO-003 legacy con handle y sin terminos es done', () {
      final legacy = _trainer(bornAt: _bornAdulto);
      expect(legacy.firstName, isNull);
      expect(legacy.lastName, isNull);
      expect(legacy.termsAcceptedAt, isNull);
      expect(hubOnboardingStage(legacy, now: _now), HubOnboardingStage.done);
      expect(
        hubOnboardingStage(
          _trainer(completo: false, bornAt: _bornAdulto),
          now: _now,
        ),
        HubOnboardingStage.pf,
      );
    });

    test('SCENARIO-004 bornAt nulo es age', () {
      expect(
        hubOnboardingStage(_trainer(), now: _now),
        HubOnboardingStage.age,
      );
    });

    group('SCENARIO-004 borde del cumpleanos 13 (barrido dia x zona)', () {
      // now = 2026-10-05. 13 años exactos: nacido 2013-10-05.
      for (final isUtc in [true, false]) {
        for (final hour in [0, 1, 12, 23]) {
          DateTime born(int d) => isUtc
              ? DateTime.utc(2013, 10, d, hour)
              : DateTime(2013, 10, d, hour);
          final now = isUtc
              ? DateTime.utc(2026, 10, 5, hour)
              : DateTime(2026, 10, 5, hour);
          final tag = 'utc=$isUtc hora=$hour';

          test('cumple 13 hoy pasa ($tag)', () {
            expect(
              hubOnboardingStage(_trainer(bornAt: born(5)), now: now),
              HubOnboardingStage.done,
            );
          });
          test('cumple 13 manana sigue en age ($tag)', () {
            expect(
              hubOnboardingStage(_trainer(bornAt: born(6)), now: now),
              HubOnboardingStage.age,
            );
          });
        }
      }
    });

    test('SCENARIO-005 displayName en blanco es identity', () {
      expect(
        hubOnboardingStage(
          _trainer(displayName: '   ', bornAt: _bornAdulto),
          now: _now,
        ),
        HubOnboardingStage.identity,
      );
      expect(
        hubOnboardingStage(
          _trainer(displayName: '', bornAt: _bornAdulto),
          now: _now,
        ),
        HubOnboardingStage.identity,
      );
    });

    test('SCENARIO-006 sin campos de alumno ni avatar es done', () {
      final p = _trainer(bornAt: _bornAdulto);
      expect(p.gymId, isNull);
      expect(p.experienceLevel, isNull);
      expect(p.gender, isNull);
      expect(p.bodyWeightKg, isNull);
      expect(p.heightCm, isNull);
      expect(p.avatarUrl, isNull);
      expect(hubOnboardingStage(p, now: _now), HubOnboardingStage.done);
    });

    test('SCENARIO-TPO-WEB-001 done implica trainerProfileComplete', () {
      final bornAts = <DateTime?>[null, _bornAdulto, DateTime.utc(2020, 1, 1)];
      for (final bornAt in bornAts) {
        for (final name in <String?>[null, '  ', 'ana']) {
          for (final completo in [true, false]) {
            final p = _trainer(
              displayName: name,
              bornAt: bornAt,
              completo: completo,
            );
            final stage = hubOnboardingStage(p, now: _now);
            if (stage == HubOnboardingStage.done) {
              expect(p.trainerProfileComplete, isTrue);
            }
            final bornOk = bornAt == _bornAdulto;
            final nameOk = name == 'ana';
            if (bornOk && nameOk) {
              expect(
                stage == HubOnboardingStage.pf,
                !p.trainerProfileComplete,
              );
            }
          }
        }
      }
    });
  });
}
