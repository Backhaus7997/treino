import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';

void main() {
  group('SidebarCollapsedNotifier (ADR-CHW-003)', () {
    test('sin clave guardada → expandido (false) [SCENARIO-756]', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SidebarCollapsedNotifier(prefs);
      expect(notifier.state, isFalse);
    });

    test('clave true guardada → restaura colapsado (true) [SCENARIO-755]',
        () async {
      SharedPreferences.setMockInitialValues({
        'coach_hub.sidebar.collapsed': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = SidebarCollapsedNotifier(prefs);
      expect(notifier.state, isTrue);
    });

    test('toggle() invierte el estado y persiste en prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SidebarCollapsedNotifier(prefs);

      await notifier.toggle();

      expect(notifier.state, isTrue);
      expect(prefs.getBool('coach_hub.sidebar.collapsed'), isTrue);
    });

    test('toggle() dos veces vuelve al estado original', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SidebarCollapsedNotifier(prefs);

      await notifier.toggle();
      await notifier.toggle();

      expect(notifier.state, isFalse);
      expect(prefs.getBool('coach_hub.sidebar.collapsed'), isFalse);
    });

    test(
        'estado persistido se restaura en un notifier nuevo (reload) '
        '[SCENARIO-755]', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = SidebarCollapsedNotifier(prefs);
      await first.toggle(); // true, persistido

      final reloadedPrefs = await SharedPreferences.getInstance();
      final reloaded = SidebarCollapsedNotifier(reloadedPrefs);

      expect(reloaded.state, isTrue);
    });
  });
}
