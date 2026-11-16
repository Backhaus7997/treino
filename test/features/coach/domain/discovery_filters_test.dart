import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/discovery_filters.dart';
import 'package:treino/features/coach_hub/domain/perfil_pf_validators.dart'
    show kPrecioMaximo, kPrecioMinimo;

/// Las tres bandas, sin `any`.
const _bandas = [PriceFilter.low, PriceFilter.mid, PriceFilter.high];

void main() {
  group('PriceFilter — bandas de precio (#1753)', () {
    test('any deja pasar todo, y un PF sin tarifa pasa por cualquier banda',
        () {
      expect(PriceFilter.any.matches(1), isTrue);
      expect(PriceFilter.any.matches(999999), isTrue);
      for (final f in PriceFilter.values) {
        expect(f.matches(null), isTrue,
            reason: '$f no filtra a quien no tiene');
      }
    });

    test('los bordes: low es estricta, mid incluye los dos extremos', () {
      expect(PriceFilter.low.matches(kPrecioBandaBajaHasta - 1), isTrue);
      expect(PriceFilter.low.matches(kPrecioBandaBajaHasta), isFalse);

      expect(PriceFilter.mid.matches(kPrecioBandaBajaHasta - 1), isFalse);
      expect(PriceFilter.mid.matches(kPrecioBandaBajaHasta), isTrue);
      expect(PriceFilter.mid.matches(kPrecioBandaMediaHasta), isTrue);
      expect(PriceFilter.mid.matches(kPrecioBandaMediaHasta + 1), isFalse);

      expect(PriceFilter.high.matches(kPrecioBandaMediaHasta), isFalse);
      expect(PriceFilter.high.matches(kPrecioBandaMediaHasta + 1), isTrue);
    });

    test('las tres bandas son una PARTICIÓN de todo el rango de tarifas válido',
        () {
      // Es el invariante que se rompió: con las bandas viejas, el rango
      // 10.001-999.999 caía entero en una sola banda y las otras dos no
      // alcanzaban a ninguna tarifa real. Cada tarifa que el onboarding deja
      // guardar tiene que caer en EXACTAMENTE una banda.
      for (var rate = kPrecioMinimo; rate <= kPrecioMaximo; rate++) {
        final cuantas = _bandas.where((b) => b.matches(rate)).length;
        if (cuantas != 1) {
          fail('la tarifa $rate cae en $cuantas bandas (tiene que ser 1)');
        }
      }
    });

    test('cada banda alcanza al menos una tarifa válida', () {
      for (final b in _bandas) {
        final hay = [
          for (var r = kPrecioMinimo; r <= kPrecioMaximo; r += 500) r,
        ].any(b.matches);
        expect(hay, isTrue, reason: '$b no matchea ninguna tarifa válida');
      }
    });

    test('las bandas cubren las tarifas reales: online, presencial, premium',
        () {
      // Los datos de precio del repo: online 20.000-40.000 y presencial
      // 90.000-155.000 (`docs/paywall-alumno-suelto.md`), el hint de 28.000
      // del Hub, el seed del emulador (38.000 / 45.000 / 52.000), premium hasta
      // 455.000. Con las bandas viejas (5.000 / 10.000) sólo `high` tenía
      // alguna.
      const tarifas = [
        20000, 28000, 38000, 40000, 45000, 52000, 90000, 125000, 155000,
        455000, //
      ];
      for (final b in _bandas) {
        expect(tarifas.any(b.matches), isTrue,
            reason: '$b sigue sin matchear ninguna tarifa real');
      }
    });

    test('las etiquetas salen de los umbrales (no se desincronizan)', () {
      expect(PriceFilter.any.label, 'Cualquier precio');
      expect(PriceFilter.low.label, 'Menos de \$40.000');
      expect(PriceFilter.mid.label, '\$40.000 - \$100.000');
      expect(PriceFilter.high.label, 'Más de \$100.000');

      expect(PriceFilter.any.chipLabel, 'Precio');
      expect(PriceFilter.low.chipLabel, '< \$40k');
      expect(PriceFilter.mid.chipLabel, '\$40-100k');
      expect(PriceFilter.high.chipLabel, '> \$100k');
    });

    test('los umbrales están ordenados y caben en el rango válido', () {
      expect(kPrecioBandaBajaHasta, greaterThan(kPrecioMinimo));
      expect(kPrecioBandaMediaHasta, greaterThan(kPrecioBandaBajaHasta));
      expect(kPrecioBandaMediaHasta, lessThan(kPrecioMaximo));
      // Las etiquetas cortas los muestran en miles.
      expect(kPrecioBandaBajaHasta % 1000, 0);
      expect(kPrecioBandaMediaHasta % 1000, 0);
    });
  });
}
