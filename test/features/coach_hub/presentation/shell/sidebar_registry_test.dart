import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

void main() {
  group('sidebarRegistry (REQ-CHW-SIDEBAR-001)', () {
    test(
        'tiene exactamente 8 items (7 post-W2 reduce + Rutinas): Dashboard, '
        'Alumnos, Agenda, Chat, Biblioteca, Rutinas, Pagos, Ajustes', () {
      // W2 reduce 2026-07-02: se removieron 12 items del sidebar que
      // duplicaban funcionalidad del alumno_detail o pertenecen a una
      // futura Biblioteca (sub-tabs). Reportes también sale (sin scope
      // definido — cuando producto lo defina se re-agrega). Sus screens y
      // rutas siguen existiendo.
      //
      // Rutinas se re-agregó al grupo RECURSOS como entrada del editor de
      // rutinas web (elegí alumno → editor), llevando el total de 7 a 8.
      expect(sidebarRegistry.length, 8);
    });

    test('cubre los 2 grupos activos post-reduce, cada uno no vacío', () {
      // CUENTA queda vacío porque Reportes se removió del registry —
      // se filtra por items.isNotEmpty en el widget y no se renderea.
      const activeGroups = [
        SidebarGroup.gestion,
        SidebarGroup.recursos,
      ];
      for (final g in activeGroups) {
        expect(
          sidebarRegistry.where((i) => i.group == g),
          isNotEmpty,
          reason: 'el grupo $g debe tener al menos un item',
        );
      }
    });

    test('los grupos legacy + CUENTA quedan sin items en el registry', () {
      // El enum los mantiene para que items futuros no rompan la firma;
      // el registry no los referencia post-reduce.
      const emptyGroups = [
        SidebarGroup.cuenta, // Reportes removido — sin scope todavía
        SidebarGroup.resumen,
        SidebarGroup.alumnos,
        SidebarGroup.plan,
        SidebarGroup.wellness,
        SidebarGroup.negocio,
        SidebarGroup.comunicacion,
      ];
      for (final g in emptyGroups) {
        expect(
          sidebarRegistry.where((i) => i.group == g),
          isEmpty,
          reason: 'group $g must not appear in the reduced registry',
        );
      }
    });

    test('el grupo ajustes tiene exactamente 1 item [SCENARIO-751]', () {
      final ajustes =
          sidebarRegistry.where((i) => i.group == SidebarGroup.ajustes);
      expect(ajustes.length, 1);
      expect(ajustes.single.id, 'ajustes');
    });

    test('los ids son únicos', () {
      final ids = sidebarRegistry.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('las rutas son únicas y coinciden con el set esperado post-reduce',
        () {
      final routes = sidebarRegistry.map((i) => i.route).toList();
      expect(routes.toSet().length, routes.length, reason: 'rutas duplicadas');
      expect(
        routes.toSet(),
        {
          '/dashboard',
          '/alumnos',
          '/agenda',
          '/chat',
          '/biblioteca',
          '/rutinas',
          '/pagos',
          '/ajustes',
        },
      );
    });

    test(
        'labels en es-AR: presentes los términos castellanos, ausentes los '
        'ingleses [SCENARIO-751]', () {
      final labels = sidebarRegistry.map((i) => i.label).toSet();

      // Equivalentes en castellano que DEBEN estar (subset post-reduce).
      for (final esLabel in [
        'Ajustes',
        'Alumnos',
        'Pagos',
        'Agenda',
        'Biblioteca',
        'Chat',
        'Dashboard',
      ]) {
        expect(labels, contains(esLabel));
      }

      // Equivalentes en inglés que NO deben aparecer.
      for (final enLabel in [
        'Settings',
        'Students',
        'Payments',
        'Schedule',
        'Library',
      ]) {
        expect(labels, isNot(contains(enLabel)));
      }
    });

    test('cada iconBuilder devuelve un IconData no nulo', () {
      for (final item in sidebarRegistry) {
        expect(item.iconBuilder(), isA<IconData>());
      }
    });

    test('todos los items arrancan sin badgeProvider en W1', () {
      for (final item in sidebarRegistry) {
        expect(item.badgeProvider, isNull);
      }
    });
  });
}
