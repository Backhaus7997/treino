// SCENARIO-CHW-ONB-062: el estampado de términos es un helper único que usan
// mobile (ProfileSetupNotifier) y el onboarding del Hub.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile_setup/application/terms_stamp.dart';

void main() {
  group('termsStampFields', () {
    test('arma los TRES campos con las versiones vigentes', () {
      final now = DateTime.utc(2026, 10, 5, 12);
      final fields = termsStampFields(now: now);

      expect(fields.keys.toSet(), {
        'termsAcceptedAt',
        'acceptedTermsVersion',
        'acceptedPrivacyVersion',
      });
      expect(fields['termsAcceptedAt'], Timestamp.fromDate(now));
      expect(fields['acceptedTermsVersion'], kTermsVersion);
      expect(fields['acceptedPrivacyVersion'], kPrivacyVersion);
    });

    test('sin now usa la hora actual en UTC', () {
      final before = DateTime.now().toUtc();
      final ts = termsStampFields()['termsAcceptedAt']! as Timestamp;
      final after = DateTime.now().toUtc();
      expect(ts.toDate().isBefore(before), isFalse);
      expect(ts.toDate().isAfter(after), isFalse);
    });
  });

  group('needsTermsStamp', () {
    test('evidencia ya observada: no estampa y NO consulta al servidor',
        () async {
      var calls = 0;
      final needs = await needsTermsStamp(
        observedHasEvidence: true,
        acceptedAtFromServer: () async {
          calls++;
          return null;
        },
      );
      expect(needs, isFalse);
      expect(calls, 0);
    });

    test('sin evidencia observada y el servidor dice null: estampa', () async {
      final needs = await needsTermsStamp(
        observedHasEvidence: false,
        acceptedAtFromServer: () async => null,
      );
      expect(needs, isTrue);
    });

    test('el servidor ya tiene termsAcceptedAt: NO pisa la evidencia',
        () async {
      final needs = await needsTermsStamp(
        observedHasEvidence: false,
        acceptedAtFromServer: () async => DateTime.utc(2026, 1, 1),
      );
      expect(needs, isFalse);
    });

    test('la consulta al servidor falla: propaga, no estampa a ciegas',
        () async {
      await expectLater(
        needsTermsStamp(
          observedHasEvidence: false,
          acceptedAtFromServer: () async => throw StateError('offline'),
        ),
        throwsStateError,
      );
    });
  });
}
