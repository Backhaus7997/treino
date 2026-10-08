// «Detectar» del lugar propio del PF pasa por el flujo único de permiso de
// ubicación (Guideline 5.1.1(iv)): nada de `Geolocator.requestPermission()`
// directo ni de un error fijo cuando el SO ya no puede preguntar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/location_permission_gateway.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_edit_trainer_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_location_permission_gateway.dart';

class _MockUserRepository extends Mock implements UserRepository {}

Position _position() => Position(
      latitude: -34.6037,
      longitude: -58.3816,
      timestamp: DateTime.utc(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Future<void> _openDetectSheet(
  WidgetTester tester,
  FakeLocationPermissionGateway gateway,
) async {
  final repo = _MockUserRepository();
  when(() => repo.update(any(), any())).thenAnswer((_) async {});
  final profile = UserProfile(
    uid: 'trainer-uid',
    email: 'trainer@example.com',
    displayName: 'Mauro PF',
    role: UserRole.trainer,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  final router = GoRouter(
    initialLocation: '/profile/edit-trainer',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE')),
        routes: [
          GoRoute(
            path: 'edit-trainer',
            builder: (_, __) =>
                const Scaffold(body: ProfileEditTrainerScreen()),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
        userProfileProvider.overrideWith((_) => Stream.value(profile)),
        userRepositoryProvider.overrideWithValue(repo),
        gymsProvider.overrideWith((ref) async => const []),
        locationPermissionGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Agregar lugar propio'));
  await tester.tap(find.text('Agregar lugar propio'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue('trainer-uid');
    registerFallbackValue(<String, Object?>{});
  });

  group('Detectar ubicación del lugar propio', () {
    testWidgets(
        'denegado de forma permanente: aviso con Ajustes, sin el error '
        'fijo ni pedido directo al SO', (tester) async {
      final gateway =
          FakeLocationPermissionGateway(LocationPermission.deniedForever);
      await _openDetectSheet(tester, gateway);

      await tester.tap(find.text('Detectar'));
      await tester.pumpAndSettle();

      expect(find.text('ABRIR AJUSTES'), findsOneWidget);
      expect(find.text('Necesitamos permiso de ubicación.'), findsNothing);
      expect(gateway.requestCalls, 0);

      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();
      expect(gateway.openSettingsCalls, 1);
    });

    testWidgets('servicios apagados: aviso de Servicios de ubicación',
        (tester) async {
      final gateway = FakeLocationPermissionGateway(
        LocationPermission.whileInUse,
        serviceEnabled: false,
      );
      await _openDetectSheet(tester, gateway);

      await tester.tap(find.text('Detectar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Activá los Servicios de ubicación'),
        findsOneWidget,
      );
      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();
      expect(gateway.openLocationSettingsCalls, 1);
    });

    testWidgets('primera vez: CONTINUAR → pedido al SO → detecta la posición',
        (tester) async {
      final gateway = FakeLocationPermissionGateway(
        LocationPermission.denied,
        requestResult: LocationPermission.whileInUse,
        position: _position(),
      );
      await _openDetectSheet(tester, gateway);

      await tester.tap(find.text('Detectar'));
      await tester.pumpAndSettle();
      expect(find.text('CONTINUAR'), findsOneWidget);
      expect(gateway.requestCalls, 0);

      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(gateway.requestCalls, 1);
      expect(find.text('-34.6037, -58.3816'), findsOneWidget);
    });

    testWidgets(
        'Android: request → deniedForever muestra el aviso del Detectar '
        '(no el de entrenadores)', (tester) async {
      final gateway = FakeLocationPermissionGateway(
        LocationPermission.denied,
        requestResult: LocationPermission.deniedForever,
      );
      await _openDetectSheet(tester, gateway);

      await tester.tap(find.text('Detectar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('para detectar tu ubicación'),
        findsOneWidget,
      );
      expect(find.textContaining('entrenadores'), findsNothing);
      expect(find.text('ABRIR AJUSTES'), findsOneWidget);
      expect(gateway.requestCalls, 1);
    });

    testWidgets('el SO deniega el pedido: mensaje de permiso, sin posición',
        (tester) async {
      final gateway = FakeLocationPermissionGateway(
        LocationPermission.denied,
        requestResult: LocationPermission.denied,
      );
      await _openDetectSheet(tester, gateway);

      await tester.tap(find.text('Detectar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(find.text('Necesitamos permiso de ubicación.'), findsOneWidget);
      expect(find.text('Sin ubicación detectada'), findsOneWidget);
    });
  });
}
