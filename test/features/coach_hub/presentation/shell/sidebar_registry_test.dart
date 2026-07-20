import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

void main() {
  group('sidebarRegistry (REQ-CHW-SIDEBAR-001)', () {
    test(
        'tiene exactamente 10 items (7 post-W2 reduce + Rutinas + Solicitudes '
        '+ Nutrición): Dashboard, Alumnos, Solicitudes, Agenda, Chat, '
        'Biblioteca, Nutrición, Rutinas, Pagos, Ajustes', () {
      // W2 reduce 2026-07-02: se removieron 12 items del sidebar que
      // duplicaban funcionalidad del alumno_detail o pertenecen a una
      // futura Biblioteca (sub-tabs). Reportes también sale (sin scope
      // definido — cuando producto lo defina se re-agrega). Sus screens y
      // rutas siguen existiendo.
      //
      // Rutinas se re-agregó al grupo RECURSOS como entrada del editor de
      // rutinas web (elegí alumno → editor), llevando el total de 7 a 8.
      //
      // Fase 4 WU-06 (ADR-F4-04): Solicitudes (ex-Invitaciones) vuelve al
      // grupo GESTIÓN, inmediatamente después de Alumnos, con badge real de
      // pendientes — llevando el total de 8 a 9.
      //
      // Fase 6 WU-06 (ADR-F6-07): Nutrición vuelve al grupo RECURSOS,
      // inmediatamente después de Biblioteca — la overview cross-alumno de
      // planes (Fase 6 WU-04) ahora es alcanzable por navegación, no solo
      // por URL directa — llevando el total de 9 a 10.
      expect(sidebarRegistry.length, 10);
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
        SidebarGroup.wellness, // Nutrición ahora vive en recursos (ADR-F6-07)
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
          '/invitaciones',
          '/agenda',
          '/chat',
          '/biblioteca',
          '/nutricion',
          '/rutinas',
          '/pagos',
          '/ajustes',
        },
      );
    });

    test(
        'Nutrición queda en RECURSOS, inmediatamente después de Biblioteca '
        '[ADR-F6-07]', () {
      final recursos = sidebarRegistry
          .where((i) => i.group == SidebarGroup.recursos)
          .map((i) => i.id)
          .toList();
      expect(recursos, ['biblioteca', 'nutricion', 'rutinas', 'pagos']);
    });

    test(
        'Solicitudes (ex-Invitaciones) queda en GESTIÓN, inmediatamente '
        'después de Alumnos [ADR-F4-04]', () {
      final gestion = sidebarRegistry
          .where((i) => i.group == SidebarGroup.gestion)
          .map((i) => i.id)
          .toList();
      expect(
        gestion,
        ['dashboard', 'alumnos', 'invitaciones', 'agenda', 'chat'],
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
        'Solicitudes',
        'Pagos',
        'Agenda',
        'Biblioteca',
        'Chat',
        'Dashboard',
        'Nutrición',
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
        'Invitations',
      ]) {
        expect(labels, isNot(contains(enLabel)));
      }
    });

    test('cada iconBuilder devuelve un IconData no nulo', () {
      for (final item in sidebarRegistry) {
        expect(item.iconBuilder(), isA<IconData>());
      }
    });

    test(
        'solo Solicitudes (fase 4, ADR-F4-04) expone badgeProvider; el '
        'resto sigue sin badge', () {
      for (final item in sidebarRegistry) {
        if (item.id == 'invitaciones') {
          expect(
            item.badgeProvider,
            isNotNull,
            reason: 'Solicitudes cablea invitacionesPendingCountProvider',
          );
        } else {
          expect(item.badgeProvider, isNull);
        }
      }
    });
  });
}
