import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:treino/core/analytics/analytics_consent.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';

/// Lo que se le mandó a Firebase, sin Firebase. `FirebaseAnalytics.instance`
/// necesita la app inicializada y un test unitario no la tiene.
class _ToggleEspia {
  final List<bool> llamadas = [];
  Future<void> call(bool enabled) async => llamadas.add(enabled);
}

(ProviderContainer, _ToggleEspia) _armar(Map<String, Object> inicial) {
  SharedPreferences.setMockInitialValues(inicial);
  final prefs = SharedPreferences.getInstance();
  final espia = _ToggleEspia();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => prefs),
      analyticsToggleProvider.overrideWithValue(espia.call),
    ],
  );
  addTearDown(container.dispose);
  return (container, espia);
}

void main() {
  group('analyticsConsentFromPrefs', () {
    test('sin nada guardado, habilitado', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(
        analyticsConsentFromPrefs(prefs),
        isTrue,
        reason: 'el default lo fija la Política: el consentimiento se presta '
            'en el alta y este interruptor es la REVOCACIÓN, no el alta',
      );
    });

    test('lee el valor guardado en false', () async {
      SharedPreferences.setMockInitialValues({kAnalyticsConsentKey: false});
      final prefs = await SharedPreferences.getInstance();

      expect(analyticsConsentFromPrefs(prefs), isFalse);
    });
  });

  group('AnalyticsConsentNotifier — cuando algo falla', () {
    // Los tres lugares que tienen que quedar de acuerdo: lo que muestra el
    // switch, lo que hace Firebase y lo que queda guardado. Si uno falla, la
    // combinacion peligrosa es «switch en apagado + recoleccion viva»: el
    // usuario cree que revoco y no revoco.

    test('si Firebase falla, el switch vuelve atras', () async {
      final llamadas = <bool>[];
      final n = AnalyticsConsentNotifier(
        (_) async => true,
        (v) async {
          llamadas.add(v);
          if (v == false) throw Exception('sin red');
        },
        inicial: true,
      );

      await n.setEnabled(false);

      expect(n.state, isTrue,
          reason: 'el switch quedo en apagado con la recoleccion todavia '
              'prendida: le miente al usuario sobre su propia revocacion');
      expect(llamadas, [false], reason: 'no reintenta al pedo el rollback');
    });

    test('si NO se pudo guardar, se vuelve atras en los tres', () async {
      final llamadas = <bool>[];
      final n = AnalyticsConsentNotifier(
        (_) async => false, // setBool devuelve false SIN tirar
        (v) async => llamadas.add(v),
        inicial: true,
      );

      await n.setEnabled(false);

      expect(n.state, isTrue,
          reason: 'un `setBool` en false es un fallo: al proximo arranque la '
              'analitica volveria sola y el switch ya decia apagado');
      expect(llamadas, [false, true],
          reason: 'no se revirtio la recoleccion despues de no poder guardar');
    });

    test('si guardar TIRA, tambien se vuelve atras', () async {
      final llamadas = <bool>[];
      final n = AnalyticsConsentNotifier(
        (_) async => throw Exception('disco lleno'),
        (v) async => llamadas.add(v),
        inicial: true,
      );

      await n.setEnabled(false);

      expect(n.state, isTrue);
      expect(llamadas, [false, true]);
    });

    test('poner el mismo valor no toca nada', () async {
      final llamadas = <bool>[];
      final n = AnalyticsConsentNotifier(
        (_) async => true,
        (v) async => llamadas.add(v),
        inicial: true,
      );

      await n.setEnabled(true);

      expect(llamadas, isEmpty,
          reason: 'una escritura y una llamada a Firebase por cada rebuild '
              'que pase el mismo valor');
    });
  });

  group('AnalyticsConsentNotifier', () {
    test('arranca en el valor persistido', () async {
      final (container, _) = _armar({kAnalyticsConsentKey: false});
      await container.read(sharedPreferencesProvider.future);

      expect(container.read(analyticsConsentProvider), isFalse);
    });

    test('apagarlo persiste Y le avisa a Firebase', () async {
      final (container, espia) = _armar({});
      await container.read(sharedPreferencesProvider.future);

      await container.read(analyticsConsentProvider.notifier).setEnabled(false);

      expect(container.read(analyticsConsentProvider), isFalse,
          reason: 'el estado de la UI no siguió al cambio');

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(prefs.getBool(kAnalyticsConsentKey), isFalse,
          reason: 'no se persistió: al reiniciar la app volvería a estar '
              'prendida, y la Política promete que la revocación vale');

      // El assert que de verdad importa: sin esto el interruptor recién haría
      // efecto al próximo arranque, y la Política dice «en cualquier momento».
      expect(espia.llamadas, [false],
          reason: 'se guardó la preferencia pero NO se apagó la recolección: '
              'Firebase sigue registrando hasta que la app reinicie');
    });

    test('volver a prenderlo también aplica', () async {
      final (container, espia) = _armar({kAnalyticsConsentKey: false});
      await container.read(sharedPreferencesProvider.future);

      await container.read(analyticsConsentProvider.notifier).setEnabled(true);

      expect(container.read(analyticsConsentProvider), isTrue);
      expect(espia.llamadas, [true]);
    });
  });
}
