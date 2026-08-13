import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/follow_status.dart';

void main() {
  // REQ-FOLLOW-002 / SCENARIO-801 — los valores de wire son los MISMOS que los
  // de `FriendshipStatus` (`'pending'` / `'accepted'`) a propósito. Inventar
  // literales nuevos obligaría a traducir en la migración y en las rules, y es
  // exactamente el tipo de drift que ya nos mordió con la lista de tipos de
  // reacción desactualizada en una Cloud Function.
  group('FollowStatus — wire values', () {
    test('round-trip fromJson/toJson para cada valor', () {
      for (final status in FollowStatus.values) {
        expect(FollowStatusX.fromJson(status.toJson()), status);
      }
    });

    test('los literales de wire son pending y accepted', () {
      expect(FollowStatus.pending.toJson(), 'pending');
      expect(FollowStatus.accepted.toJson(), 'accepted');
    });

    test('fromJson resuelve los literales conocidos', () {
      expect(FollowStatusX.fromJson('pending'), FollowStatus.pending);
      expect(FollowStatusX.fromJson('accepted'), FollowStatus.accepted);
    });

    test('un valor desconocido tira ArgumentError, no devuelve un default', () {
      // Fallar ruidoso: un status que no reconocemos es dato corrupto o un
      // cliente de otra versión, y tratarlo como `pending` por descarte
      // otorgaría o negaría acceso en silencio.
      expect(() => FollowStatusX.fromJson('rejected'), throwsArgumentError);
      expect(() => FollowStatusX.fromJson(''), throwsArgumentError);
      expect(() => FollowStatusX.fromJson('Accepted'), throwsArgumentError);
    });
  });
}
