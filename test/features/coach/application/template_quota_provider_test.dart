// template_quota_provider_test.dart — [templateUsageSummaryProvider] lee
// SÓLO el documento del PF (docs/limite-plantillas-pf.md §3 PR5), calcado de
// `customExerciseUsageSummaryProvider`. El eje es el mismo: "no sé" (contador
// ausente) nunca colapsa a "cero".

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

const _uid = 'trainer-1';

/// Container con `users/{_uid}` sembrado tal cual se pasa. Sin colección de
/// plantillas: este provider no la lee — esa es la diferencia con el
/// eventual gate de PR3.
Future<ProviderContainer> _containerConDoc(Map<String, Object?> doc) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc(_uid).set({'uid': _uid, ...doc});
  final container = ProviderContainer(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(_uid),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<TemplateQuota?> _leerResumen(ProviderContainer c) async {
  final sub = c.listen(templateUsageSummaryProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  final v = sub.read();
  expect(v.hasValue, isTrue);
  return v.valueOrNull;
}

void main() {
  group('templateUsageSummaryProvider (sólo el documento del PF)', () {
    test('tope y contador del documento', () async {
      final c = await _containerConDoc({
        'planLimits': {'templates': 3},
        'templateUsage': {'count': 2},
      });
      expect(await _leerResumen(c), (limit: 3, count: 2));
    });

    test('tope null ⇒ sin límite, con el contador igual', () async {
      final c = await _containerConDoc({
        'planLimits': {'templates': null},
        'templateUsage': {'count': 5},
      });
      expect(await _leerResumen(c), (limit: null, count: 5));
    });

    test('tope ausente (interruptor apagado o Plan pago) ⇒ sin límite',
        () async {
      final c = await _containerConDoc({
        'templateUsage': {'count': 1},
      });
      expect(await _leerResumen(c), (limit: null, count: 1));
    });

    test('⚠️ contador ausente ⇒ null («no sé»), nunca count 0', () async {
      final c = await _containerConDoc({
        'planLimits': {'templates': 3},
      });
      expect(await _leerResumen(c), isNull);
    });

    test('contador con otra forma ⇒ null', () async {
      final c = await _containerConDoc({
        'templateUsage': {'count': '2'},
      });
      expect(await _leerResumen(c), isNull);
    });

    test('sin uid ⇒ null de inmediato, sin round-trip', () async {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(templateUsageSummaryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(sub.read().valueOrNull, isNull);
    });
  });
}
