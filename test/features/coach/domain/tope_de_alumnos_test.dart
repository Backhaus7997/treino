/// tope_de_alumnos_test.dart — cómo se lee `planLimits.athletes*` del doc del PF.
///
/// Lo que protege: que «el servidor todavía no lo dijo» (clave ausente, o doc
/// que no se entiende) no se confunda NUNCA con «el servidor dijo sin tope»
/// (`athletes: null`). Colapsar los dos le mostraría «sin tope» a un PF que
/// nunca sincronizó.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/tope_de_alumnos.dart';

void main() {
  final borde = DateTime.utc(2026, 10, 15, 15);

  group('TopeDeAlumnosPublicado.leer — ausente no es «sin tope»', () {
    test('sin `planLimits`, o con otra forma: no publicado', () {
      expect(TopeDeAlumnosPublicado.leer(null), isA<TopeNoPublicado>());
      expect(TopeDeAlumnosPublicado.leer('x'), isA<TopeNoPublicado>());
      expect(TopeDeAlumnosPublicado.leer(7), isA<TopeNoPublicado>());
    });

    test('mapa con los otros topes pero sin `athletes`: no publicado', () {
      expect(
        TopeDeAlumnosPublicado.leer({'customExercises': 60, 'templates': null}),
        isA<TopeNoPublicado>(),
      );
      // Un doc degradado puede traer sólo `athletesHasta` sin `athletes`.
      expect(
        TopeDeAlumnosPublicado.leer(
            {'athletesHasta': Timestamp.fromDate(borde)}),
        isA<TopeNoPublicado>(),
      );
    });

    test('`athletes: null` EXPLÍCITO: publicado, sin tope', () {
      final t = TopeDeAlumnosPublicado.leer({'athletes': null});
      expect(t, isA<TopePublicado>());
      expect((t as TopePublicado).limite, isNull);
    });

    test('`athletes: 7`: publicado, con tope', () {
      final t = TopeDeAlumnosPublicado.leer({
        'athletes': 7,
        'athletesHasta': null,
        'athletesDespues': null,
      });
      expect(t, const TopePublicado(limite: 7));
    });

    test('ausente y null no son iguales entre sí', () {
      expect(
        TopeDeAlumnosPublicado.leer({'customExercises': 1}),
        isNot(TopeDeAlumnosPublicado.leer({'athletes': null})),
      );
    });

    test('un entero que llegó como double (7.0) vale 7', () {
      expect(
        TopeDeAlumnosPublicado.leer({'athletes': 7.0}),
        const TopePublicado(limite: 7),
      );
    });

    test('`athletes` que no se entiende (texto, decimales): no publicado', () {
      for (final raro in <Object>['siete', 7.5, true, <int>[]]) {
        expect(
          TopeDeAlumnosPublicado.leer({'athletes': raro}),
          isA<TopeNoPublicado>(),
          reason: '$raro',
        );
      }
    });
  });

  group('TopeDeAlumnosPublicado.leer — el cambio programado', () {
    test('con `athletesHasta`, lee `athletesDespues`', () {
      expect(
        TopeDeAlumnosPublicado.leer({
          'athletes': 7,
          'athletesHasta': Timestamp.fromDate(borde),
          'athletesDespues': 2,
        }),
        TopePublicado(limite: 7, hasta: borde, despues: 2),
      );
    });

    test('`athletesDespues: null` CON `athletesHasta` es «sin tope» después',
        () {
      final t = TopeDeAlumnosPublicado.leer({
        'athletes': 7,
        'athletesHasta': Timestamp.fromDate(borde),
        'athletesDespues': null,
      }) as TopePublicado;

      expect(t.hasta, borde);
      expect(t.despues, isNull);
      expect(t.vigenteEn(borde.add(const Duration(minutes: 1))), isNull);
      expect(t.vigenteEn(borde.subtract(const Duration(minutes: 1))), 7);
    });

    test(
        'con `athletesHasta` pero sin `athletesDespues`: doc roto, no publicado',
        () {
      expect(
        TopeDeAlumnosPublicado.leer({
          'athletes': 7,
          'athletesHasta': Timestamp.fromDate(borde),
        }),
        isA<TopeNoPublicado>(),
      );
      expect(
        TopeDeAlumnosPublicado.leer({
          'athletes': 7,
          'athletesHasta': Timestamp.fromDate(borde),
          'athletesDespues': 'dos',
        }),
        isA<TopeNoPublicado>(),
      );
    });

    test('un `athletesHasta` que no es Timestamp: doc roto, no publicado', () {
      for (final raro in <Object>['mañana', 1790000000000, true]) {
        expect(
          TopeDeAlumnosPublicado.leer({
            'athletes': 7,
            'athletesHasta': raro,
            'athletesDespues': 2,
          }),
          isA<TopeNoPublicado>(),
          reason: '$raro',
        );
      }
    });

    test('`athletesHasta` null o ausente: sin cambio programado', () {
      expect(
        TopeDeAlumnosPublicado.leer({'athletes': 7, 'athletesHasta': null}),
        const TopePublicado(limite: 7),
      );
      expect(
        TopeDeAlumnosPublicado.leer({'athletes': 7}),
        const TopePublicado(limite: 7),
      );
    });
  });

  group('TopeDeAlumnosPublicado.leer — topes no positivos', () {
    test('`athletes` en 0 o negativo: no publicado, no «0 DE 0»', () {
      for (final raro in <Object>[0, -1, -7, 0.0]) {
        expect(
          TopeDeAlumnosPublicado.leer({'athletes': raro}),
          isA<TopeNoPublicado>(),
          reason: '$raro',
        );
      }
    });

    test('`athletesDespues` en 0 o negativo con borde: no publicado', () {
      for (final raro in <Object>[0, -2]) {
        expect(
          TopeDeAlumnosPublicado.leer({
            'athletes': 7,
            'athletesHasta': Timestamp.fromDate(borde),
            'athletesDespues': raro,
          }),
          isA<TopeNoPublicado>(),
          reason: '$raro',
        );
      }
    });

    test('el borde inferior válido es 1', () {
      expect(
        TopeDeAlumnosPublicado.leer({'athletes': 1}),
        const TopePublicado(limite: 1),
      );
    });
  });

  group('igualdad por valor', () {
    test('dos TopeNoPublicado son iguales aunque no sean el mismo const', () {
      // ignore: prefer_const_constructors
      final a = TopeNoPublicado();
      // ignore: prefer_const_constructors
      final b = TopeNoPublicado();

      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('no publicado y publicado nunca son iguales', () {
      expect(const TopeNoPublicado(), isNot(const TopePublicado(limite: null)));
    });

    test('dos TopePublicado con los mismos campos comparten hashCode', () {
      final a = TopePublicado(limite: 7, hasta: borde, despues: 2);
      final b = TopePublicado(limite: 7, hasta: borde, despues: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('TopePublicado — qué rige y cuándo hay que volver a mirar', () {
    final t = TopePublicado(limite: 7, hasta: borde, despues: 2);

    test('antes del borde rige `limite`; EN el borde ya rige `despues`', () {
      expect(t.vigenteEn(borde.subtract(const Duration(milliseconds: 1))), 7);
      expect(t.vigenteEn(borde), 2);
      expect(t.vigenteEn(borde.add(const Duration(days: 1))), 2);
    });

    test('el próximo cambio es el borde mientras no pasó, y nada después', () {
      expect(t.proximoCambioDesde(borde.subtract(const Duration(hours: 1))),
          borde);
      expect(t.proximoCambioDesde(borde), isNull);
      expect(t.proximoCambioDesde(borde.add(const Duration(hours: 1))), isNull);
    });

    test('sin `hasta` no hay borde', () {
      const sinBorde = TopePublicado(limite: 7);
      expect(sinBorde.proximoCambioDesde(borde), isNull);
      expect(sinBorde.vigenteEn(borde), 7);
    });

    test('compara por valor', () {
      expect(
        TopePublicado(limite: 7, hasta: borde, despues: 2),
        TopePublicado(limite: 7, hasta: borde, despues: 2),
      );
      expect(const TopePublicado(limite: 7),
          isNot(const TopePublicado(limite: 2)));
    });
  });

  group('tierConTope', () {
    test('cada número de la tabla da su tier, y null (sin tope) da Plan 3', () {
      expect(tierConTope(2), SubscriptionTier.free);
      expect(tierConTope(7), SubscriptionTier.plan1);
      expect(tierConTope(15), SubscriptionTier.plan2);
      expect(tierConTope(null), SubscriptionTier.plan3);
    });

    test('un número que ninguna tabla tiene: null, no un tier inventado', () {
      expect(tierConTope(9), isNull);
      expect(tierConTope(0), isNull);
    });

    test('es inversa de la tabla: ida y vuelta para todos los tiers', () {
      for (final tier in SubscriptionTier.values) {
        expect(tierConTope(tier.weightLimit), tier);
      }
    });
  });
}
