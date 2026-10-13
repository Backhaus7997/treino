// "OTRO GYM / SIN GYM" + GUARDAR con la secuencia REAL: un usuario que hoy
// tiene un gym de Places elegido, toca OTRO y guarda. Usa el UserRepository
// verdadero sobre un Firestore falso (no un mock): lo que se mide es lo que
// queda escrito, no que se haya llamado a `update`.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_gym_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

const _uid = 'test-uid';

Future<FakeFirebaseFirestore> _seed(String? gymId) async {
  final fs = FakeFirebaseFirestore();
  final now = DateTime.utc(2026, 1, 1);
  final profile = UserProfile(
    uid: _uid,
    email: 't@t.com',
    displayName: 'Test',
    role: UserRole.athlete,
    createdAt: now,
    updatedAt: now,
    gymId: gymId,
  );
  await fs.collection('users').doc(_uid).set(profile.toJson());
  await fs.collection('userPublicProfiles').doc(_uid).set({
    'uid': _uid,
    'displayName': 'Test',
    'gymId': gymId,
    'gymName': gymId == null ? null : 'Un gym',
  });
  return fs;
}

Widget _app(FakeFirebaseFirestore fs) {
  final router = GoRouter(
    initialLocation: '/profile/gym',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE_SCREEN')),
        routes: [
          GoRoute(
            path: 'gym',
            builder: (_, __) => const Scaffold(body: ProfileGymScreen()),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(_MockUser())),
      firestoreProvider.overrideWithValue(fs),
      userRepositoryProvider.overrideWithValue(
        UserRepository(firestore: fs, gyms: GymRepository(firestore: fs)),
      ),
      nearbyLocationProvider.overrideWith(
        (ref) => NearbyLocationNotifier()..setDeniedForTest(),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

Future<void> _tocarOtroYGuardar(WidgetTester tester) async {
  await tester.tap(find.text('OTRO GYM / SIN GYM'));
  await tester.pump();
  await tester.tap(find.text('GUARDAR'));
  await tester.pumpAndSettle();
}

void main() {
  group('Perfil > Gimnasio > OTRO GYM / SIN GYM', () {
    testWidgets('un usuario con gym real que elige SIN GYM queda con null',
        (tester) async {
      final fs = await _seed('ChIJreal');
      await tester.pumpWidget(_app(fs));
      await tester.pumpAndSettle();

      await _tocarOtroYGuardar(tester);

      final priv = (await fs.collection('users').doc(_uid).get()).data()!;
      final pub =
          (await fs.collection('userPublicProfiles').doc(_uid).get()).data()!;
      expect(priv['gymId'], isNull);
      expect(pub['gymId'], isNull);
      expect(find.text('PROFILE_SCREEN'), findsOneWidget);
    });

    testWidgets(
        'un usuario con el centinela legacy "no-gym" ve OTRO seleccionado y '
        'GUARDAR deshabilitado hasta que toque algo', (tester) async {
      final fs = await _seed('no-gym');
      await tester.pumpWidget(_app(fs));
      await tester.pumpAndSettle();

      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'GUARDAR'),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets(
        'con "no-gym" legacy guardado, tocar OTRO habilita GUARDAR y lo migra '
        'a null', (tester) async {
      final fs = await _seed('no-gym');
      await tester.pumpWidget(_app(fs));
      await tester.pumpAndSettle();

      await _tocarOtroYGuardar(tester);

      final priv = (await fs.collection('users').doc(_uid).get()).data()!;
      final pub =
          (await fs.collection('userPublicProfiles').doc(_uid).get()).data()!;
      expect(priv['gymId'], isNull);
      expect(pub['gymId'], isNull);
    });

    testWidgets(
        'si el perfil llega DESPUÉS de abrir la pantalla, el borrador no queda '
        'clavado en null', (tester) async {
      final fs = await _seed('ChIJreal');
      await tester.pumpWidget(_app(fs));
      // Sin pumpAndSettle: la primera construcción ve el perfil en carga.
      await tester.pump();
      await tester.pumpAndSettle();

      // Con un gym real vigente y SIN tocar nada, GUARDAR tiene que seguir
      // deshabilitado; si no, un solo tap escribiría `null` encima del gym.
      final boton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'GUARDAR'),
      );
      expect(boton.onPressed, isNull);
    });
  });
}
