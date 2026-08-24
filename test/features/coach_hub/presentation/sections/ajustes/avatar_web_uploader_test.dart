// Tests de `AvatarWebUploader.deleteStored()` — regresión de #765 (QA-SEC-009).
//
// Hasta #765 este método envolvía el `delete()` en un `catch (_) {}` vacío. Y
// como la regla de Storage no declaraba `allow delete`, el borrado caía en
// `write` —que dereferencia `request.resource.size`, null en un delete— y se
// denegaba SIEMPRE, incluso para el dueño. El resultado combinado era que
// "Quitar foto" mostraba "Foto quitada" mientras el objeto seguía en el bucket.
//
// El contrato correcto es el mismo que ya usaban PostPhotoUploadService,
// ChatMediaUploadService, AthleteFileRepository y CustomExerciseVideoUploadService:
// tolerar SÓLO `object-not-found` y propagar todo lo demás.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/avatar_web_uploader.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockRef extends Mock implements Reference {}

void main() {
  late _MockAuth auth;
  late _MockUser user;
  late _MockStorage storage;
  late _MockRef rootRef;
  late _MockRef avatarRef;

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    storage = _MockStorage();
    rootRef = _MockRef();
    avatarRef = _MockRef();

    when(() => user.uid).thenReturn('pf1');
    when(() => auth.currentUser).thenReturn(user);
    when(() => storage.ref()).thenReturn(rootRef);
    when(() => rootRef.child(any())).thenReturn(avatarRef);
  });

  AvatarWebUploader uploader() =>
      AvatarWebUploader(storage: storage, auth: auth);

  test('borra avatars/{uid}.jpg del usuario autenticado', () async {
    when(() => avatarRef.delete()).thenAnswer((_) async {});

    await uploader().deleteStored();

    verify(() => rootRef.child('avatars/pf1.jpg')).called(1);
    verify(() => avatarRef.delete()).called(1);
  });

  test('tolera object-not-found — para el usuario eso ES el estado deseado',
      () async {
    when(() => avatarRef.delete()).thenThrow(
      FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
    );

    await expectLater(uploader().deleteStored(), completes);
  });

  test('PROPAGA cualquier otro error de Storage — no vuelve al catch vacío',
      () async {
    // Éste es el caso que #765 desenterró: la regla denegaba el borrado hasta
    // para el dueño y el `catch (_) {}` se comía el `unauthorized`, así que la
    // UI mostraba éxito. Si alguien vuelve a poner un catch amplio, este test
    // se pone rojo.
    when(() => avatarRef.delete()).thenThrow(
      FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'),
    );

    await expectLater(
      uploader().deleteStored(),
      throwsA(isA<FirebaseException>()
          .having((e) => e.code, 'code', 'unauthorized')),
    );
  });

  test('no toca Storage si no hay usuario autenticado', () async {
    when(() => auth.currentUser).thenReturn(null);

    await uploader().deleteStored();

    verifyNever(() => storage.ref());
  });
}
