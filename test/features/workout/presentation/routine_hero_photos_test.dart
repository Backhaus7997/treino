import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';

void main() {
  test(
    'routineIdsWithHeroPhoto coincide con los JPG de assets/routines/',
    () {
      final enDisco = Directory('assets/routines')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.jpg'))
          .map((n) => n.substring(0, n.length - '.jpg'.length))
          .toSet();

      expect(
        routineIdsWithHeroPhoto,
        enDisco,
        reason: 'Sumaste o sacaste una foto de assets/routines/ sin '
            'actualizar routineIdsWithHeroPhoto (o al revés).',
      );
    },
  );

  test('toda plantilla del catálogo tiene foto', () {
    final catalogo = jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>;
    final ids = catalogo.map((t) => (t as Map)['id'] as String).toSet();

    expect(ids, isNotEmpty);
    expect(
      ids.difference(routineIdsWithHeroPhoto),
      isEmpty,
      reason: 'Plantillas sin foto en assets/routines/{id}.jpg: agregá la '
          'foto y el id a routineIdsWithHeroPhoto.',
    );
    for (final id in ids) {
      expect(
        File('assets/routines/$id.jpg').existsSync(),
        isTrue,
        reason: 'Falta assets/routines/$id.jpg',
      );
    }
  });
}
