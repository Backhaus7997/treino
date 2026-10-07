import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/location_permission_flow.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../../helpers/fake_location_permission_gateway.dart';

/// Monta un botón GO que corre el flujo y guarda lo que devolvió.
class _Harness {
  _Harness(this.gateway);

  final FakeLocationPermissionGateway gateway;
  bool? proceed;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('es', 'AR'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: locale,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  proceed = await presentLocationPermissionFlow(
                    context,
                    gateway,
                  );
                },
                child: const Text('GO'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('presentLocationPermissionFlow', () {
    testWidgets(
        'permiso aún no pedido: muestra el sheet y CONTINUAR devuelve '
        'true para que el caller pida el permiso al SO', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.denied),
      );
      await h.pump(tester);

      expect(find.text('CONTINUAR'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      expect(h.proceed, isNull, reason: 'el flujo espera al usuario');

      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(h.proceed, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
      expect(h.gateway.openSettingsCalls, 0);
    });

    testWidgets('ya otorgado: no muestra nada y deja seguir', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.whileInUse),
      );
      await h.pump(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(h.proceed, isTrue);
    });

    testWidgets(
        'error del plugin: se trata como "no pedido" y muestra el '
        'sheet', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(
          LocationPermission.denied,
          throwOnCheck: true,
        ),
      );
      await h.pump(tester);

      expect(find.text('CONTINUAR'), findsOneWidget);
    });

    testWidgets(
        'denegado de forma permanente: NO muestra el sheet previo; '
        'muestra el aviso con acceso a Ajustes', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.deniedForever),
      );
      await h.pump(tester);

      expect(find.text('CONTINUAR'), findsNothing);
      expect(find.text('Permitir ubicación'), findsNothing);
      expect(
        find.textContaining(
          'Activá la ubicación en Ajustes para ver entrenadores cerca tuyo',
        ),
        findsOneWidget,
      );
      expect(find.text('ABRIR AJUSTES'), findsOneWidget);
      expect(find.text('Seguir sin ubicación'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      expect(h.gateway.openSettingsCalls, 0);
    });

    testWidgets('el aviso en inglés', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.deniedForever),
      );
      await h.pump(tester, locale: const Locale('en'));

      expect(find.text('OPEN SETTINGS'), findsOneWidget);
      expect(find.text('Continue without location'), findsOneWidget);
    });

    testWidgets(
        'ABRIR AJUSTES abre los Ajustes de la app y no pide el '
        'permiso', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.deniedForever),
      );
      await h.pump(tester);

      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();

      expect(h.gateway.openSettingsCalls, 1);
      expect(h.proceed, isFalse);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
        '«Seguir sin ubicación» cierra sin abrir Ajustes ni pedir '
        'permiso', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(LocationPermission.deniedForever),
      );
      await h.pump(tester);

      await tester.tap(find.text('Seguir sin ubicación'));
      await tester.pumpAndSettle();

      expect(h.gateway.openSettingsCalls, 0);
      expect(h.proceed, isFalse);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
