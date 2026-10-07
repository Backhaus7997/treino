import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/location_permission_gateway.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/presentation/trainers_list_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_location_permission_gateway.dart';

/// Guideline 5.1.1(iv) (build 1.0 (54), iPad Air M3): en Descubrir
/// entrenadores el mensaje previo al permiso de ubicación tenía «Aceptar» y
/// «Ahora no». Acá se fija que el usuario SIEMPRE llega al pedido del SO, y
/// que cuando el SO ya no puede preguntar se ofrece Ajustes.
class _RecordingAthleteLocationNotifier extends AthleteLocationNotifier {
  int requestPermissionCalls = 0;

  @override
  Future<void> requestPermission() async {
    requestPermissionCalls++;
    setDeniedForTest();
  }
}

Future<_RecordingAthleteLocationNotifier> _pump(
  WidgetTester tester,
  FakeLocationPermissionGateway gateway,
) async {
  final notifier = _RecordingAthleteLocationNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerDiscoveryProvider.overrideWith((_) async => const []),
        athleteLocationProvider.overrideWith((ref) => notifier),
        locationPermissionGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const TrainersListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  group('TrainersListScreen — permiso de ubicación', () {
    testWidgets(
        'primera vez: mensaje con un solo CONTINUAR; al tocarlo se '
        'pide el permiso al SO', (tester) async {
      final notifier = await _pump(
        tester,
        FakeLocationPermissionGateway(LocationPermission.denied),
      );

      expect(find.text('CONTINUAR'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('ACEPTAR'), findsNothing);
      expect(notifier.requestPermissionCalls, 0);

      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(notifier.requestPermissionCalls, 1);
    });

    testWidgets(
        'el mensaje no se puede saltear: tocar afuera no pide ni '
        'cierra', (tester) async {
      final notifier = await _pump(
        tester,
        FakeLocationPermissionGateway(LocationPermission.denied),
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.text('CONTINUAR'), findsOneWidget);
      expect(notifier.requestPermissionCalls, 0);
    });

    testWidgets(
        'denegado de forma permanente: al abrir NO se muestra nada ni se '
        'pide al SO; la pantalla queda usable sin ubicación', (tester) async {
      final gateway =
          FakeLocationPermissionGateway(LocationPermission.deniedForever);
      final notifier = await _pump(tester, gateway);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('ABRIR AJUSTES'), findsNothing);
      expect(find.text('CONTINUAR'), findsNothing);
      expect(notifier.requestPermissionCalls, 0);
      expect(notifier.isPermissionDenied, isTrue);
      expect(gateway.openSettingsCalls, 0);
      expect(find.textContaining('ENCONTRÁ TU COACH'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);
    });

    testWidgets(
        'servicios de ubicación apagados: al abrir tampoco se muestra '
        'nada', (tester) async {
      final notifier = await _pump(
        tester,
        FakeLocationPermissionGateway(
          LocationPermission.denied,
          serviceEnabled: false,
        ),
      );

      expect(find.byType(BottomSheet), findsNothing);
      expect(notifier.requestPermissionCalls, 0);
      expect(notifier.isPermissionDenied, isTrue);
    });

    testWidgets(
        'denegado de forma permanente: tocar el chip Distancia (acción del '
        'usuario) sí muestra el aviso con Ajustes', (tester) async {
      final gateway =
          FakeLocationPermissionGateway(LocationPermission.deniedForever);
      final notifier = await _pump(tester, gateway);

      await tester.tap(find.text('Distancia'));
      await tester.pumpAndSettle();

      expect(find.text('ABRIR AJUSTES'), findsOneWidget);
      expect(find.text('CONTINUAR'), findsNothing);

      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();

      expect(gateway.openSettingsCalls, 1);
      expect(notifier.requestPermissionCalls, 0);
    });
  });
}
