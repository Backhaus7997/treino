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

    test('quedan exactamente 3 gratis — el free tiene con qué entrenar', () {
      // Si esto baja a 0, el plan gratis se queda sin ningún programa que
      // seguir y el catálogo deja de ser una razón para instalar la app.
      final gratis = templates
          .cast<Map<String, dynamic>>()
          .where((t) => t['isPremium'] == false)
          .toList();
      expect(gratis, hasLength(3));
      expect(
        gratis.map((t) => t['id']),
        containsAll(['ppl-beginner', 'full-body-3day', 'calistenia-beginner']),
      );
    });

    test('NINGUNA plantilla paga entra en la forma del plan gratis', () {
      // ─── El candado que el servidor no puede poner ───────────────────────
      //
      // `isPremium` frena ENTRENAR la plantilla (el CREATE de `sessions` lo
      // mira). No frena COPIARLA: el CREATE de `/routines` no mira ese campo
      // ni una vez, y no puede — el payload de una rutina copiada es idéntico
      // al de una escrita a mano. El servidor no tiene con qué distinguirlos.
      //
      // Lo único que queda en pie es la FORMA. Si una plantilla paga entra en
      // `withinFreeRoutineShape` —hasta 3 días y 1 semana—, un alumno free la
      // copia, el servidor la acepta, y desde ahí la entrena para siempre sin
      // pasar por ningún gate: la copia es `user-created` y el cliente nunca
      // escribe `isPremium`.
      //
      // El 2026-09-14 `hipertrofia-intermedio` entraba EXACTO: 3 días, sin
      // `numWeeks`. Se la llevó a 6 (PPL dos veces por semana), que además
      // resolvió que fuera casi un clon de `ppl-beginner` —3 días, PPL, 58
      // series contra 60— o sea que se cobraba por un 3% más de volumen.
      //
      // Este test es lo que evita que vuelva sola. No es un detalle de
      // implementación: es el único lugar del repo donde el candado del
      // catálogo es verificable.
      const maxDiasFree = 3; // kFreeMaxRoutineDays
      const maxSemanasFree = 1; // kFreeMaxRoutineWeeks

      for (final t in templates.cast<Map<String, dynamic>>()) {
        if (t['isPremium'] != true) continue;
        final dias = (t['days'] as List<dynamic>).length;
        final semanas = (t['numWeeks'] as int?) ?? 1;
        expect(
          dias > maxDiasFree || semanas > maxSemanasFree,
          isTrue,
          reason:
              '${t['id']} tiene $dias día(s) y $semanas semana(s): entra en la '
              'forma free, así que un alumno gateado puede copiarla y el '
              'servidor no tiene con qué rebotarla.',
        );
      }
    });
  });
}
