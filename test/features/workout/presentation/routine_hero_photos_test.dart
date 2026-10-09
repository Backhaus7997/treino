import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';

void main() {
  test(
    'routineIdsWithHeroPhoto coincide con los PNG de assets/routines/',
    () {
      final enDisco = Directory('assets/routines')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.png'))
          .map((n) => n.substring(0, n.length - '.png'.length))
          .toSet();

      expect(
        routineIdsWithHeroPhoto,
        enDisco,
        reason: 'Sumaste o sacaste una foto de assets/routines/ sin '
            'actualizar routineIdsWithHeroPhoto (o al revés).',
      );
    },
  );
}
