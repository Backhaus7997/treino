import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/ajustes_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _trainer() => UserProfile(
  uid: 'pf1',
  email: 'sofia@treino.app',
  displayName: 'Sofía Ramírez',
  role: UserRole.trainer,
  createdAt: DateTime(2025, 1, 1),
  updatedAt: DateTime(2025, 1, 1),
);

Widget _harness() => ProviderScope(
  overrides: [
    userProfileProvider.overrideWith(
      (ref) => Stream<UserProfile?>.value(_trainer()),
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: AjustesScreen())),
);

void main() {
  group('AjustesScreen (W3.1)', () {
    testWidgets('renderiza el header y las 4 tabs de Configuración', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('Cuenta'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text('Facturación TREINO'), findsOneWidget);
      expect(find.text('Datos y privacidad'), findsOneWidget);
    });

    testWidgets('la tab Cuenta muestra los datos del PF logueado', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('INFORMACIÓN PERSONAL'), findsOneWidget);
      expect(find.text('Sofía Ramírez'), findsOneWidget);
      expect(find.text('sofia@treino.app'), findsOneWidget);
      expect(find.text('ZONA PELIGROSA'), findsOneWidget);
    });

    testWidgets('tocar Notificaciones cambia el cuerpo del tab', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.tap(find.text('Notificaciones'));
      await tester.pump();

      expect(find.text('Notificaciones · Próximamente'), findsOneWidget);
      expect(find.text('INFORMACIÓN PERSONAL'), findsNothing);
    });
  });
}
