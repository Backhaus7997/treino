import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';

class _MockUser extends Mock implements User {}

User _usuario(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

Future<void> _asentar() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> sembrar(Map<String, Object?> data) =>
      firestore.collection('app_config').doc('pdf_import').set(data);

  ProviderContainer contenedor(Stream<User?> auth) {
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      authStateChangesProvider.overrideWith((_) => auth),
    ]);
    addTearDown(c.dispose);
    // Mantiene vivo el provider entre lecturas.
    c.listen(pdfImportGateProvider, (_, __) {});
    return c;
  }

  group('pdfImportEnabledFor', () {
    test('enabled: true habilita a cualquiera', () {
      expect(pdfImportEnabledFor({'enabled': true}, 'u'), isTrue);
    });

    test('apagado pero en allowlistUids: habilitado', () {
      expect(
          pdfImportEnabledFor({
            'enabled': false,
            'allowlistUids': ['u']
          }, 'u'),
          isTrue);
    });

    test('apagado y fuera de la allowlist: no', () {
      expect(
          pdfImportEnabledFor({
            'enabled': false,
            'allowlistUids': ['otro']
          }, 'u'),
          isFalse);
    });

    test('sin documento o con enabled no booleano: no (falla cerrado)', () {
      expect(pdfImportEnabledFor(null, 'u'), isFalse);
      expect(pdfImportEnabledFor({'enabled': 'true'}, 'u'), isFalse);
    });
  });

  group('pdfImportGateProvider', () {
    test('mientras auth no resolvió: loading, NO disabled', () {
      final c = contenedor(StreamController<User?>().stream);

      expect(c.read(pdfImportGateProvider), PdfImportGate.loading);
    });

    test('habilitado por allowlist', () async {
      await sembrar({
        'enabled': false,
        'allowlistUids': ['pf-1']
      });
      final c = contenedor(Stream.value(_usuario('pf-1')));
      await _asentar();

      expect(c.read(pdfImportGateProvider), PdfImportGate.enabled);
    });

    test('sin documento: disabled', () async {
      final c = contenedor(Stream.value(_usuario('pf-1')));
      await _asentar();

      expect(c.read(pdfImportGateProvider), PdfImportGate.disabled);
    });

    test('sin sesión: disabled', () async {
      final c = contenedor(Stream.value(null));
      await _asentar();

      expect(c.read(pdfImportGateProvider), PdfImportGate.disabled);
    });

    test('apagarlo en vivo esconde el CTA', () async {
      await sembrar({'enabled': true});
      final c = contenedor(Stream.value(_usuario('pf-1')));
      await _asentar();
      expect(c.read(pdfImportGateProvider), PdfImportGate.enabled);

      await sembrar({'enabled': false});
      await _asentar();

      expect(c.read(pdfImportGateProvider), PdfImportGate.disabled);
    });

    test('error de auth: disabled', () async {
      final c = contenedor(Stream.error(StateError('x')));
      await _asentar();

      expect(c.read(pdfImportGateProvider), PdfImportGate.disabled);
    });
  });
}
