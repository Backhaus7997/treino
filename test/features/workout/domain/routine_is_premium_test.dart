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
  });
}
