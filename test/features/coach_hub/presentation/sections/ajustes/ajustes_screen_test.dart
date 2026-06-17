import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/ajustes_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/avatar_web_uploader.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUserRepo extends Mock implements UserRepository {}

class _MockUploader extends Mock implements AvatarWebUploader {}

UserProfile _trainer() => UserProfile(
      uid: 'pf1',
      email: 'sofia@treino.app',
      displayName: 'Sofía Ramírez',
      role: UserRole.trainer,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

Widget _harness({
  UserProfile? profile,
  UserRepository? repo,
  AvatarWebUploader? uploader,
}) =>
    ProviderScope(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile ?? _trainer()),
        ),
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(const [])),
        webNotificationPreferencesProvider.overrideWith(
          (ref) => Stream<NotifPrefs>.value(NotifPrefs.fromFirestore(null)),
        ),
        if (repo != null) userRepositoryProvider.overrideWithValue(repo),
        if (uploader != null)
          avatarWebUploaderProvider.overrideWithValue(uploader),
      ],
      child: const MaterialApp(home: Scaffold(body: AjustesScreen())),
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('AjustesScreen (W3.1)', () {
    testWidgets('renderiza el header y las 4 tabs de Configuración',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('Cuenta'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text('Facturación TREINO'), findsOneWidget);
      expect(find.text('Datos y privacidad'), findsOneWidget);
    });

    testWidgets('la tab Cuenta muestra los datos del PF logueado',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('INFORMACIÓN PERSONAL'), findsOneWidget);
      expect(find.text('Sofía Ramírez'), findsOneWidget);
      expect(find.text('sofia@treino.app'), findsOneWidget);
      expect(find.text('ZONA PELIGROSA'), findsOneWidget);
    });

    testWidgets('tocar Notificaciones cambia el cuerpo del tab',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.tap(find.text('Notificaciones'));
      await tester.pump();
      await tester.pump(); // deja emitir el StreamProvider de prefs

      // Ya no es placeholder: muestra la matriz real.
      expect(find.text('NOTIFICACIONES'), findsOneWidget);
      expect(find.text('PUSH'), findsOneWidget);
      expect(find.text('INFORMACIÓN PERSONAL'), findsNothing);
    });

    testWidgets('Notificaciones: togglear un canal persiste notificationPrefs',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      await tester.tap(find.text('Notificaciones'));
      await tester.pump();
      await tester.pump(); // deja emitir el StreamProvider de prefs

      // Primer checkbox = pago_recibido × EMAIL (default on) → lo apago.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      final captured = verify(() => repo.update('pf1', captureAny()))
          .captured
          .single as Map<String, Object?>;
      final prefs = captured['notificationPrefs'] as Map<String, dynamic>;
      expect((prefs['pago_recibido'] as Map)['email'], false);
      expect((prefs['pago_recibido'] as Map)['push'], true);
    });

    testWidgets(
        'GUARDAR CAMBIOS persiste nombre/apellido + displayName derivado',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      // NOMBRE es el primer TextField.
      await tester.enterText(find.byType(TextField).first, 'Mateo');
      await tester.pump();
      await tester.tap(find.text('GUARDAR CAMBIOS'));
      await tester.pump();

      final captured = verify(() => repo.update('pf1', captureAny()))
          .captured
          .single as Map<String, Object?>;
      expect(captured['firstName'], 'Mateo');
      expect(captured['lastName'], 'Ramírez');
      expect(captured['displayName'], 'Mateo Ramírez');
    });

    testWidgets('GUARDAR CAMBIOS no guarda si NOMBRE queda vacío',
        (tester) async {
      final repo = _MockUserRepo();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.text('GUARDAR CAMBIOS'));
      await tester.pump();

      verifyNever(() => repo.update(any(), any()));
    });

    testWidgets('CAMBIAR FOTO sube la imagen y persiste avatarUrl',
        (tester) async {
      final repo = _MockUserRepo();
      final uploader = _MockUploader();
      when(() => uploader.pickAndUpload())
          .thenAnswer((_) async => 'https://cdn/avatar.jpg');
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(repo: repo, uploader: uploader));
      await tester.pump();

      await tester.tap(find.text('CAMBIAR FOTO'));
      await tester.pump();
      await tester.pump();

      verify(() => uploader.pickAndUpload()).called(1);
      verify(() => repo.update('pf1', {'avatarUrl': 'https://cdn/avatar.jpg'}))
          .called(1);
    });

    testWidgets('QUITAR borra el blob de Storage y limpia avatarUrl',
        (tester) async {
      final repo = _MockUserRepo();
      final uploader = _MockUploader();
      when(() => uploader.deleteStored()).thenAnswer((_) async {});
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_harness(
        profile: _trainer().copyWith(avatarUrl: 'https://cdn/old.jpg'),
        repo: repo,
        uploader: uploader,
      ));
      await tester.pump();

      await tester.tap(find.text('QUITAR'));
      await tester.pump();
      await tester.pump();

      verify(() => uploader.deleteStored()).called(1);
      verify(() => repo.update('pf1', {'avatarUrl': null})).called(1);
    });
  });
}
