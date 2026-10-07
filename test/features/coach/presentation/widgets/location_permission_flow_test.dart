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
  LocationFlowOutcome? outcome;
  bool? get proceed => outcome?.proceed;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('es', 'AR'),
    bool interactive = true,
    LocationPurpose purpose = LocationPurpose.trainers,
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
                  outcome = await presentLocationPermissionFlow(
                    context,
                    gateway,
                    interactive: interactive,
                    purpose: purpose,
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
        FakeLocationPermissionGateway(
          LocationPermission.denied,
          requestResult: LocationPermission.whileInUse,
        ),
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
      expect(find.text('TU UBICACIÓN'), findsNothing);
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

    group('Servicios de ubicación apagados', () {
      testWidgets(
          'muestra el aviso de Servicios de ubicación (no el CONTINUAR) y '
          'no deja seguir', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester);

        expect(find.text('CONTINUAR'), findsNothing);
        expect(
          find.textContaining('Activá los Servicios de ubicación en Ajustes'),
          findsOneWidget,
        );
        expect(find.text('ABRIR AJUSTES'), findsOneWidget);
        expect(find.text('Seguir sin ubicación'), findsOneWidget);
        expect(h.gateway.requestCalls, 0);
      });

      testWidgets(
          'aunque el permiso ya esté otorgado, sin servicios no hay '
          'posición: muestra el aviso', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.whileInUse,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester);

        expect(find.text('ABRIR AJUSTES'), findsOneWidget);
        expect(h.proceed, isNull);
      });

      testWidgets(
          'ABRIR AJUSTES abre los ajustes de ubicación, no los de la app',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester);

        await tester.tap(find.text('ABRIR AJUSTES'));
        await tester.pumpAndSettle();

        expect(h.gateway.openLocationSettingsCalls, 1);
        expect(h.gateway.openSettingsCalls, 0);
        expect(h.proceed, isFalse);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('«Seguir sin ubicación» cierra sin abrir nada',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester);

        await tester.tap(find.text('Seguir sin ubicación'));
        await tester.pumpAndSettle();

        expect(h.gateway.openLocationSettingsCalls, 0);
        expect(h.gateway.openSettingsCalls, 0);
        expect(h.proceed, isFalse);
      });

      testWidgets('un error al consultar los servicios no bloquea el flujo',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            throwOnServiceCheck: true,
          ),
        );
        await h.pump(tester);

        expect(find.text('CONTINUAR'), findsOneWidget);
      });

      testWidgets('el aviso en inglés', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester, locale: const Locale('en'));

        expect(
            find.textContaining('Turn on Location Services'), findsOneWidget);
        expect(find.text('OPEN SETTINGS'), findsOneWidget);
      });
    });

    group('interactive: false (apertura de pantalla)', () {
      testWidgets('denegado de forma permanente: no muestra nada',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await h.pump(tester, interactive: false);

        expect(find.byType(BottomSheet), findsNothing);
        expect(h.proceed, isFalse);
        expect(h.gateway.openSettingsCalls, 0);
      });

      testWidgets('servicios apagados: no muestra nada', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester, interactive: false);

        expect(find.byType(BottomSheet), findsNothing);
        expect(h.proceed, isFalse);
      });

      testWidgets('primera vez: sí muestra el CONTINUAR', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.denied),
        );
        await h.pump(tester, interactive: false);

        expect(find.text('CONTINUAR'), findsOneWidget);
      });
    });

    group('el sheet CONTINUAR no se puede cerrar', () {
      testWidgets(
          'ni la barrera, ni arrastrar, ni «atrás»; sólo CONTINUAR cierra',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            requestResult: LocationPermission.whileInUse,
          ),
        );
        await h.pump(tester);
        expect(find.text('CONTINUAR'), findsOneWidget);

        // Barrera.
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(find.text('CONTINUAR'), findsOneWidget);

        // Arrastre hacia abajo.
        await tester.fling(find.text('CONTINUAR'), const Offset(0, 400), 1500);
        await tester.pumpAndSettle();
        expect(find.text('CONTINUAR'), findsOneWidget);

        // «Atrás» del sistema.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('CONTINUAR'), findsOneWidget);
        expect(h.proceed, isNull);

        await tester.tap(find.text('CONTINUAR'));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        expect(h.proceed, isTrue,
            reason: 'el caller recibe true y pide al SO de inmediato');
      });
    });

    group('Android: check() dice denied aunque el SO ya no pregunta', () {
      // En Android `checkPermission()` mapea todo lo no otorgado a `denied`;
      // sólo `requestPermission()` devuelve `deniedForever`.
      testWidgets(
          'interactivo: CONTINUAR → request devuelve deniedForever → aviso de '
          'Ajustes de inmediato', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            requestResult: LocationPermission.deniedForever,
          ),
        );
        await h.pump(tester);
        await tester.tap(find.text('CONTINUAR'));
        await tester.pumpAndSettle();

        expect(h.gateway.requestCalls, 1);
        expect(find.text('ABRIR AJUSTES'), findsOneWidget);
        expect(h.outcome, isNull, reason: 'el aviso sigue abierto');

        await tester.tap(find.text('ABRIR AJUSTES'));
        await tester.pumpAndSettle();
        expect(h.gateway.openSettingsCalls, 1);
        expect(h.outcome, LocationFlowOutcome.blocked);
      });

      testWidgets('no interactivo: sigue en silencio, sin aviso',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            requestResult: LocationPermission.deniedForever,
          ),
        );
        await h.pump(tester, interactive: false);
        await tester.tap(find.text('CONTINUAR'));
        await tester.pumpAndSettle();

        expect(find.text('ABRIR AJUSTES'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(h.outcome, LocationFlowOutcome.blocked);
      });

      testWidgets('request otorga: el caller puede seguir', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            requestResult: LocationPermission.whileInUse,
          ),
        );
        await h.pump(tester);
        await tester.tap(find.text('CONTINUAR'));
        await tester.pumpAndSettle();

        expect(h.outcome, LocationFlowOutcome.granted);
        expect(find.text('ABRIR AJUSTES'), findsNothing);
      });

      testWidgets('el usuario rechaza el diálogo del SO: denied, sin aviso',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.denied),
        );
        await h.pump(tester);
        await tester.tap(find.text('CONTINUAR'));
        await tester.pumpAndSettle();

        expect(h.outcome, LocationFlowOutcome.denied);
        expect(find.text('ABRIR AJUSTES'), findsNothing);
      });
    });

    group('textos por propósito', () {
      testWidgets('gimnasios: aviso habla de gimnasios y de buscar por nombre',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await h.pump(tester, purpose: LocationPurpose.nearbyGyms);

        expect(
          find.text(
            'Activá la ubicación en Ajustes para ver gimnasios cerca tuyo. '
            'Mientras tanto podés buscarlo por nombre.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('entrenadores'), findsNothing);
        expect(find.textContaining('Online'), findsNothing);
      });

      testWidgets('gimnasios: el mensaje previo habla de gimnasios',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.denied),
        );
        await h.pump(tester, purpose: LocationPurpose.nearbyGyms);

        expect(find.textContaining('gimnasios cerca tuyo'), findsOneWidget);
        expect(find.textContaining('entrenadores'), findsNothing);
      });

      testWidgets('gimnasios, servicios apagados', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await h.pump(tester, purpose: LocationPurpose.nearbyGyms);

        expect(find.textContaining('ver gimnasios cerca tuyo'), findsOneWidget);
        expect(find.textContaining('Online'), findsNothing);
      });

      testWidgets('detectar (PF): aviso habla de detectar la ubicación',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await h.pump(tester, purpose: LocationPurpose.trainerDetect);

        expect(
          find.text(
            'Activá la ubicación en Ajustes para detectar tu ubicación. '
            'También podés elegir un gimnasio de la lista.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Online'), findsNothing);
      });

      testWidgets('detectar (PF): mensaje previo y servicios apagados',
          (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.denied),
        );
        await h.pump(tester, purpose: LocationPurpose.trainerDetect);
        expect(find.textContaining('detectar'), findsOneWidget);
        expect(find.textContaining('entrenadores'), findsNothing);
      });

      testWidgets('en inglés, por propósito', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await h.pump(
          tester,
          locale: const Locale('en'),
          purpose: LocationPurpose.nearbyGyms,
        );
        expect(find.textContaining('gyms near you'), findsOneWidget);
        expect(find.textContaining('trainers'), findsNothing);
      });
    });

    group('títulos en MAYÚSCULAS (AGENTS.md §2: headings UPPERCASE)', () {
      testWidgets('mensaje previo', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.denied),
        );
        await h.pump(tester);
        expect(find.text('TU UBICACIÓN'), findsOneWidget);
        expect(find.text('Tu ubicación'), findsNothing);
      });

      testWidgets('aviso de permiso y de servicios apagados', (tester) async {
        final a = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await a.pump(tester);
        expect(find.text('UBICACIÓN DESACTIVADA'), findsOneWidget);
        expect(find.text('Ubicación desactivada'), findsNothing);
      });

      testWidgets('servicios apagados', (tester) async {
        final b = _Harness(
          FakeLocationPermissionGateway(
            LocationPermission.denied,
            serviceEnabled: false,
          ),
        );
        await b.pump(tester);
        expect(
            find.text('SERVICIOS DE UBICACIÓN DESACTIVADOS'), findsOneWidget);
      });

      testWidgets('en inglés', (tester) async {
        final h = _Harness(
          FakeLocationPermissionGateway(LocationPermission.deniedForever),
        );
        await h.pump(tester, locale: const Locale('en'));
        expect(find.text('LOCATION IS OFF'), findsOneWidget);
      });
    });

    testWidgets(
        'si abrir Ajustes lanza, el aviso se cierra igual y no hay error '
        'sin manejar', (tester) async {
      final h = _Harness(
        FakeLocationPermissionGateway(
          LocationPermission.deniedForever,
          throwOnOpenSettings: true,
        ),
      );
      await h.pump(tester);

      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(h.proceed, isFalse);
    });
  });
}
