import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/location_permission_gateway.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_advanced_filter_chips.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../../helpers/fake_location_permission_gateway.dart';

/// El chip «Distancia» sin ubicación abría un sheet propio («ACTIVÁ TU
/// UBICACIÓN», «Ahora no» / «Activar») antes del pedido del SO: el mismo
/// patrón que Apple rechazó (5.1.1(iv)). Ahora comparte el flujo único.
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
  final notifier = _RecordingAthleteLocationNotifier()..setDeniedForTest();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        athleteLocationProvider.overrideWith((ref) => notifier),
        locationPermissionGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerAdvancedFilterChips()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  group('Chip Distancia sin ubicación', () {
    testWidgets(
        'permiso no pedido: mensaje con un solo CONTINUAR que lleva '
        'al pedido del SO', (tester) async {
      final notifier = await _pump(
        tester,
        FakeLocationPermissionGateway(
          LocationPermission.denied,
          requestResult: LocationPermission.whileInUse,
        ),
      );

      await tester.tap(find.text('Distancia'));
      await tester.pumpAndSettle();

      expect(find.text('CONTINUAR'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('Activar'), findsNothing);

      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(notifier.requestPermissionCalls, 1);
    });

    testWidgets(
        'denegado de forma permanente: aviso con Ajustes, sin pedir '
        'al SO', (tester) async {
      final gateway =
          FakeLocationPermissionGateway(LocationPermission.deniedForever);
      final notifier = await _pump(tester, gateway);

      await tester.tap(find.text('Distancia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();

      expect(gateway.openSettingsCalls, 1);
      expect(notifier.requestPermissionCalls, 0);
    });

    testWidgets(
        'Android: check dice denied pero el SO ya no pregunta (request → '
        'deniedForever): aviso de Ajustes de inmediato', (tester) async {
      final gateway = FakeLocationPermissionGateway(
        LocationPermission.denied,
        requestResult: LocationPermission.deniedForever,
      );
      final notifier = await _pump(tester, gateway);

      await tester.tap(find.text('Distancia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(find.text('ABRIR AJUSTES'), findsOneWidget);
      await tester.tap(find.text('ABRIR AJUSTES'));
      await tester.pumpAndSettle();
      expect(gateway.openSettingsCalls, 1);
      expect(notifier.requestPermissionCalls, 0,
          reason: 'el notifier no vuelve a pedir lo que el flujo ya pidió');
    });

    testWidgets('el usuario rechaza el diálogo: queda «sin ubicación»',
        (tester) async {
      final notifier = await _pump(
        tester,
        FakeLocationPermissionGateway(LocationPermission.denied),
      );

      await tester.tap(find.text('Distancia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(notifier.requestPermissionCalls, 0);
      expect(notifier.isPermissionDenied, isTrue);
      expect(find.text('ABRIR AJUSTES'), findsNothing);
    });
  });
}
