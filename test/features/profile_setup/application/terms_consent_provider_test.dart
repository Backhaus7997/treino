import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile_setup/application/terms_consent_provider.dart';

UserProfile _perfil({DateTime? termsAcceptedAt}) => UserProfile(
      uid: 'u1',
      email: 'a@b.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 9, 22),
      updatedAt: DateTime.utc(2026, 9, 22),
      termsAcceptedAt: termsAcceptedAt,
    );

void main() {
  ProviderContainer contenedor(Stream<UserProfile?> Function() perfil) {
    final c = ProviderContainer(overrides: [
      userProfileProvider.overrideWith((ref) => perfil()),
    ]);
    addTearDown(c.dispose);
    // Mantiene vivo el provider derivado mientras el stream emite.
    c.listen(termsConsentRequiredProvider, (_, __) {});
    return c;
  }

  group('termsConsentRequiredProvider — se decide por evidencia', () {
    // EL caso por el que existe el provider. Así nace el doc de un alta con
    // Google/Apple cuando el create del login anda: existe, y sin
    // `termsAcceptedAt`. La versión anterior («sin perfil = hace falta») daba
    // `false` acá, y esas cuentas terminaban el alta sin consentimiento.
    test('perfil SIN termsAcceptedAt → hace falta (true)', () async {
      final c = contenedor(() => Stream.value(_perfil()));
      await c.read(userProfileProvider.future);

      expect(c.read(termsConsentRequiredProvider), isTrue);
    });

    test('perfil CON termsAcceptedAt (alta por email) → no hace falta',
        () async {
      final c = contenedor(
        () => Stream.value(_perfil(termsAcceptedAt: DateTime.utc(2026, 9, 1))),
      );
      await c.read(userProfileProvider.future);

      expect(c.read(termsConsentRequiredProvider), isFalse);
    });

    test('sin doc (el create del login falló) → hace falta (true)', () async {
      final c = contenedor(() => Stream<UserProfile?>.value(null));
      await c.read(userProfileProvider.future);

      expect(c.read(termsConsentRequiredProvider), isTrue);
    });

    // «No sé» no es «no hay»: con `valueOrNull` estos dos casos colapsaban en
    // null, y null se leía como «perfil ausente → pedir». El provider los
    // devuelve como null explícito para que cada lector decida.
    test('perfil todavía cargando → no se sabe (null)', () {
      final nunca = StreamController<UserProfile?>();
      addTearDown(nunca.close);
      final c = contenedor(() => nunca.stream);

      expect(c.read(termsConsentRequiredProvider), isNull);
    });

    test('stream en error sin valor previo → no se sabe (null)', () async {
      final c = contenedor(
        () => Stream<UserProfile?>.error(StateError('permission-denied')),
      );
      await expectLater(c.read(userProfileProvider.future), throwsStateError);

      expect(c.read(termsConsentRequiredProvider), isNull);
    });
  });
}
