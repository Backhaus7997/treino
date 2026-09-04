// consentimiento-legal-versionado — R4.
//
// Strict TDD: artefacto RED del grupo 12.
//
// El gate del aviso NO se apoya en `acceptedPrivacyVersion`: como no hay
// backfill, TODA cuenta anterior al feature tiene ese campo en null, así que
// no distingue a nadie. La única evidencia que existe hoy en producción es
// `termsAcceptedAt`, y por eso la comparación es contra
// `kPrivacyV1PublishedAt`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile/application/legacy_privacy_notice_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _profile({
  required UserRole role,
  DateTime? termsAcceptedAt,
}) =>
    UserProfile(
      uid: 'u1',
      email: 'u@test.com',
      displayName: 'U',
      role: role,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      termsAcceptedAt: termsAcceptedAt,
    );

ProviderContainer _container(UserProfile? profile) {
  final container = ProviderContainer(
    overrides: [
      userProfileProvider.overrideWith(
        (_) => profile == null
            ? const Stream<UserProfile>.empty()
            : Stream.value(profile),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Espera a que el stream del perfil emita antes de leer el gate.
Future<void> _settle(ProviderContainer c) async {
  await c.read(userProfileProvider.future);
}

void main() {
  final before = kPrivacyV1PublishedAt.subtract(const Duration(days: 30));
  final after = kPrivacyV1PublishedAt.add(const Duration(days: 1));

  group('R4: a quién le corresponde el aviso de política actualizada', () {
    test('atleta que aceptó ANTES de la política vigente ⇒ sí', () async {
      final c = _container(
        _profile(role: UserRole.athlete, termsAcceptedAt: before),
      );
      await _settle(c);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isTrue);
    });

    test('atleta al día ⇒ no', () async {
      final c = _container(
        _profile(role: UserRole.athlete, termsAcceptedAt: after),
      );
      await _settle(c);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isFalse);
    });

    test('entrenador ⇒ no (le corresponde el sheet, no el aviso)', () async {
      final c = _container(
        _profile(role: UserRole.trainer, termsAcceptedAt: before),
      );
      await _settle(c);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isFalse);
    });

    test('sin evidencia de aceptación ⇒ no', () async {
      // `termsAcceptedAt == null` es la cuenta legacy pre-QA-AUTH-001: no
      // sabemos qué aceptó ni cuándo. Avisarle "actualizamos la política"
      // afirmaría un hecho que no tenemos — §11.1.
      final c = _container(
        _profile(role: UserRole.athlete, termsAcceptedAt: null),
      );
      await _settle(c);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isFalse);
    });

    test('perfil todavía no cargado ⇒ no', () async {
      final c = _container(null);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isFalse);
    });

    test('descartado en esta sesión ⇒ no', () async {
      final c = _container(
        _profile(role: UserRole.athlete, termsAcceptedAt: before),
      );
      await _settle(c);
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isTrue);

      c.read(legacyPrivacyNoticeDismissedProvider.notifier).markDismissed();
      expect(c.read(shouldShowLegacyPrivacyNoticeProvider), isFalse);
    });
  });
}
