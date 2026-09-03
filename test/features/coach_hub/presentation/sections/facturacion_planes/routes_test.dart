// La ruta REAL del Coach Hub, no un stand-in.
//
// Los dos test files del slice arman su propio router de juguete: uno monta la
// pantalla pelada en `/` y el otro registra un stub que dibuja un `Text`. Los
// dos validan el string del `push` contra su propia copia del literal, así que
// borrar el GoRoute de producción dejaba analyze en 0 y la suite entera en
// verde — con el banner de denegación mandando al PF a la página de error de
// go_router justo cuando más necesita la respuesta.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/blocked_athletes_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/routes.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

void main() {
  group('facturacionPlanesRoutes', () {
    test('registra la ruta de alumnos en solo lectura', () {
      final paths = facturacionPlanesRoutes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toList();

      expect(paths, contains(kBlockedStudentsRoutePath));
    });

    test('el path es exactamente el que se comunica', () {
      // La constante la comparten `routes.dart` y el banner del editor, así
      // que la comparación entre ellos se cumpliría sola. Lo que este assert
      // pinea es el VALOR: la URL ya se puede haber compartido o guardado, y
      // renombrarla en silencio rompe los links que ya existen.
      expect(kBlockedStudentsRoutePath, '/facturacion/alumnos-solo-lectura');
    });
  });

  testWidgets('navegar a la ruta real monta BlockedStudentsScreen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: kBlockedStudentsRoutePath,
      // Sin `routes:` propias: se monta la lista de PRODUCCIÓN tal cual la
      // consume `coach_hub_router.dart`.
      routes: facturacionPlanesRoutes,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockedAthletesProvider.overrideWith(
            (ref) => Stream.value(const BlockedAthletes.published({'a1'})),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(
              UserProfile(
                uid: 'pf1',
                email: 'pf@test.com',
                displayName: 'Profe',
                role: UserRole.trainer,
                createdAt: DateTime(2025),
                updatedAt: DateTime(2025),
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BlockedStudentsScreen), findsOneWidget);
    expect(find.text('ALUMNOS EN SOLO LECTURA'), findsOneWidget);
  });
}
