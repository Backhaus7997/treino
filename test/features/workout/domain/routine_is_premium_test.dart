// `isPremium` — el campo del catálogo pago (paywall del alumno, spec §4.1.1).
//
// El test que importa acá es el PRIMERO, y no es sobre el paywall: es sobre no
// romper toda la creación de rutinas del atleta.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

Routine _routine({bool isPremium = false}) => Routine(
      id: 'r-1',
      name: 'Push Pull Legs',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.system,
      isPremium: isPremium,
    );

void main() {
  group('isPremium NUNCA sale en un payload de escritura', () {
    test('toJson() no lo emite, ni en true ni en false', () {
      // ⚠️ Si este test se pone rojo, NO lo arregles cambiando el expect.
      //
      // `firestore.rules` valida las rutinas `user-created` con un
      // `hasOnly(userCreatedRoutineFields())`, y esa lista NO conoce
      // `isPremium`. El día que `toJson()` lo emita, TODA creación y TODA
      // edición de rutina de atleta empieza a fallar con permission-denied —
      // el modo de falla de #563, que el propio archivo de reglas advierte en
      // su COUPLING WARNING.
      //
      // El campo lo siembra `scripts/seed_templates.js` con el Admin SDK, que
      // saltea las reglas. El cliente sólo lo lee.
      expect(
          _routine(isPremium: true).toJson().containsKey('isPremium'), isFalse);
      expect(_routine().toJson().containsKey('isPremium'), isFalse);
    });

    test('fromJson() sí lo lee', () {
      final json = _routine().toJson()
        ..['id'] = 'r-1'
        ..['isPremium'] = true;
      expect(Routine.fromJson(json).isPremium, isTrue);
    });

    test('un doc sin el campo es GRATIS', () {
      // Es el estado de los 7 docs en producción hasta que se corra el seed.
      // El default tiene que abrir, no cobrar: un error de siembra falla del
      // lado seguro.
      final json = _routine().toJson()..['id'] = 'r-1';
      expect(json.containsKey('isPremium'), isFalse);
      expect(Routine.fromJson(json).isPremium, isFalse);
    });
  });

  group('el seed del catálogo', () {
    late List<dynamic> templates;

    setUpAll(() {
      templates = jsonDecode(
        File('docs/video-catalog-audit/improved-templates.json')
            .readAsStringSync(),
      ) as List<dynamic>;
    });

    test('las 3 de principiante son gratis y las otras 4 no', () {
      // El corte de la spec §4.1.1. Se assertea contra el `level` de cada
      // plantilla y no contra una lista de ids escrita a mano: así, agregar
      // una plantilla nueva al catálogo sin decidir su precio rompe acá en vez
      // de shipear con un default silencioso.
      for (final t in templates.cast<Map<String, dynamic>>()) {
        final esPrincipiante = t['level'] == 'beginner';
        expect(
          t['isPremium'],
          esPrincipiante ? isFalse : isTrue,
          reason: '${t['id']} es ${t['level']}',
        );
      }
    });

    test('quedan exactamente 15 gratis — el free tiene con qué entrenar', () {
      // Si esto baja a 0, el plan gratis se queda sin ningún programa que
      // seguir y el catálogo deja de ser una razón para instalar la app.
      //
      // Eran 3 hasta que el catálogo pasó de 7 a 50 (octubre de 2026): las
      // 15 de principiante son gratis, el mismo corte por nivel de siempre.
      final gratis = templates
          .cast<Map<String, dynamic>>()
          .where((t) => t['isPremium'] == false)
          .toList();
      expect(gratis, hasLength(15));
      expect(
        gratis.map((t) => t['id']),
        containsAll(['ppl-beginner', 'full-body-3day', 'calistenia-beginner']),
      );
    });

    test(
        'las pagas que entran en la forma free son un conjunto ACEPTADO y '
        'cerrado', () {
      // ─── Decisión de producto, 2026-10-09: el dueño ACEPTÓ este hueco ────
      //
      // `isPremium` frena ENTRENAR la plantilla (el CREATE de `sessions` lo
      // mira). Antes del #1155 la única traba contra COPIARLA era la FORMA:
      // si una plantilla paga entraba en `withinFreeRoutineShape` (hasta 3
      // días y 1 semana), un alumno free la copiaba y el servidor la aceptaba.
      // Este test exigía que NINGUNA pagada entrara, y por eso estuvo en rojo
      // cuando el catálogo pasó de 7 a 50: 13 pagas tienen <=3 días y 1 semana.
      //
      // Desde el #1155 el candado REAL es otro: el CREATE de `/routines`
      // rechaza las copias selladas con `copiedFrom` apuntando a una
      // plantilla del sistema cuando el paywall está activo
      // (`copiadaDelCatalogo()` en firestore.rules y su cláusula en el create).
      // Copiar vía la app ("Usar como base") queda bloqueado en el servidor
      // para CUALQUIER plantilla paga, entre en la forma free o no. Ese sello
      // lo prueba `routine_editor_paywall_test.dart` ("EL SELLO: la copia
      // guardada lleva `copiedFrom` con la fuente"); si el editor deja de
      // estamparlo, esa suite se pone roja.
      //
      // Lo que queda abierto es tipear a mano una rutina de <=3 días en el
      // editor, y ninguna regla puede frenarlo (el propio comentario de las
      // reglas lo dice). El dueño lo aceptó.
      //
      // Qué guarda este test: el conjunto aceptado es EXPLÍCITO. Una plantilla
      // paga NUEVA que entre en la forma free rompe acá y obliga a decidirlo
      // a conciencia (agregarla a la lista, o darle más días/semanas).
      const aceptadas = {
        'alta-intensidad-1-serie-avanzado',
        'cinco-por-cinco-rampa-intermedio',
        'complejo-pesas-rusas-intermedio',
        'fuerza-3dias-avanzado',
        'fuerza-corredores-intermedio',
        'full-body-2dias-avanzado',
        'full-body-2dias-intermedio',
        'halterofilia-inicial-intermedio',
        'pesa-rusa-funcional-intermedio',
        'piramide-inversa-3dias-intermedio',
        'rendimiento-deportivo-intermedio',
        'volumen-10x10-avanzado',
        'volumen-recuperacion-intensidad-intermedio',
      };
      const maxDiasFree = 3; // kFreeMaxRoutineDays
      const maxSemanasFree = 1; // kFreeMaxRoutineWeeks

      final entranEnLaFormaFree = <String>{};
      for (final t in templates.cast<Map<String, dynamic>>()) {
        if (t['isPremium'] != true) continue;
        final dias = (t['days'] as List<dynamic>).length;
        final semanas = (t['numWeeks'] as int?) ?? 1;
        if (dias <= maxDiasFree && semanas <= maxSemanasFree) {
          entranEnLaFormaFree.add(t['id'] as String);
        }
      }

      expect(
        entranEnLaFormaFree,
        aceptadas,
        reason: 'El conjunto de pagas que caben en el plan gratis cambió. '
            'Ya no es una traba (la traba es el sello `copiedFrom`, #1155), '
            'pero sumar una nueva es una decisión: agregala a `aceptadas` o '
            'dale más de $maxDiasFree días / $maxSemanasFree semana.',
      );
    });
  });
}
