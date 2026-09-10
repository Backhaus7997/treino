import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/coach_hub/application/picker_panel_width_provider.dart';

Future<ProviderContainer> _container(
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
  ]);
  // El provider es un `FutureProvider` y el notifier hace `requireValue`: sin
  // esperar la resolución, la primera lectura explota con `AsyncLoading`.
  await c.read(sharedPreferencesProvider.future);
  return c;
}

void main() {
  group('maxAnchoPanelPicker — la rutina no cede nunca', () {
    // El tope no es un número elegido: es el que YA se envía. A 1280 de
    // viewport con el sidebar de 240 afuera quedan 1040, el panel se lleva 400
    // y a la rutina le quedan 640. El arrastre nunca puede dejar el editor
    // peor de lo que hoy funciona.
    test('a 1040 de ancho el panel no pasa de 400', () {
      expect(maxAnchoPanelPicker(1040), 400);
    });

    test('con más pantalla, el panel puede crecer', () {
      expect(maxAnchoPanelPicker(1440),
          640); // 1440-640 = 800, capado por el techo
      expect(maxAnchoPanelPicker(1200), 560);
    });

    test('a la rutina SIEMPRE le quedan 640 o más', () {
      for (final ancho in [1000, 1040, 1100, 1280, 1440, 1680, 1920]) {
        final panel = maxAnchoPanelPicker(ancho.toDouble());
        expect(ancho - panel, greaterThanOrEqualTo(kAnchoMinimoRutina),
            reason: 'a $ancho px el panel se lleva $panel y le deja '
                '${ancho - panel} a la rutina');
      }
    });

    test('en un ancho apretado gana el piso del panel, no un negativo', () {
      // 800-640 = 160, abajo del piso. Sin el `math.max` el panel mediría 160
      // y la lista sería ilegible; peor, con menos de 640 daría NEGATIVO y el
      // `clamp` reventaría con min > max.
      expect(maxAnchoPanelPicker(800), kAnchoPanelPickerMin);
      expect(maxAnchoPanelPicker(500), kAnchoPanelPickerMin);
    });
  });

  group('PickerPanelWidthNotifier', () {
    test('arranca en el default y persiste lo arrastrado', () async {
      final c = await _container();
      addTearDown(c.dispose);
      expect(c.read(pickerPanelWidthProvider), kAnchoPanelPickerDefault);

      c.read(pickerPanelWidthProvider.notifier).ajustar(80, maxAncho: 640);
      expect(c.read(pickerPanelWidthProvider), 480);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getDouble('coach_hub.picker_panel.width'), 480);
    });

    test('vuelve a abrir con lo que se dejó', () async {
      final c = await _container({'coach_hub.picker_panel.width': 520.0});
      addTearDown(c.dispose);
      expect(c.read(pickerPanelWidthProvider), 520);
    });

    // El caso que el clamp-al-dibujar solo no arregla: ensanchar en el monitor
    // grande, abrir en la laptop. Acotar sólo al pintar dejaría el número malo
    // guardado para siempre.
    test('un ancho guardado que ya no entra se corrige al tocarlo', () async {
      final c = await _container({'coach_hub.picker_panel.width': 620.0});
      addTearDown(c.dispose);

      c
          .read(pickerPanelWidthProvider.notifier)
          .ajustar(10, maxAncho: maxAnchoPanelPicker(1040));

      expect(c.read(pickerPanelWidthProvider), 400);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getDouble('coach_hub.picker_panel.width'), 400,
          reason: 'el valor corregido tiene que quedar EN PREFS, no sólo en '
              'pantalla');
    });

    test('no baja del piso por más que se arrastre', () async {
      final c = await _container();
      addTearDown(c.dispose);
      c.read(pickerPanelWidthProvider.notifier).ajustar(-9999, maxAncho: 640);
      expect(c.read(pickerPanelWidthProvider), kAnchoPanelPickerMin);
    });
  });
}
