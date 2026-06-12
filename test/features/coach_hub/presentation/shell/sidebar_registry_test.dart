import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

void main() {
  group('sidebarRegistry (REQ-CHW-SIDEBAR-001)', () {
    test('tiene exactamente 19 items [SCENARIO-750]', () {
      // El spec dice "21" pero la enumeración real (tabla del spec + lista de
      // rutas de W1.1.7) es 19; Solicitudes y Perfil Público quedan fuera de W1.
      expect(sidebarRegistry.length, 19);
    });

    test('cubre los 6 grupos no-ajustes, cada uno no vacío [SCENARIO-750]', () {
      const nonAjustes = [
        SidebarGroup.resumen,
        SidebarGroup.alumnos,
        SidebarGroup.plan,
        SidebarGroup.wellness,
        SidebarGroup.negocio,
        SidebarGroup.comunicacion,
      ];
      for (final g in nonAjustes) {
        expect(
          sidebarRegistry.where((i) => i.group == g),
          isNotEmpty,
          reason: 'el grupo $g debe tener al menos un item',
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

    test('las rutas son únicas y coinciden con el set esperado', () {
      final routes = sidebarRegistry.map((i) => i.route).toList();
      expect(routes.toSet().length, routes.length, reason: 'rutas duplicadas');
      expect(
        routes.toSet(),
        {
          '/dashboard',
          '/actividad',
          '/agenda',
          '/alumnos',
          '/invitaciones',
          '/cuestionario',
          '/rutinas',
          '/planner',
          '/biblioteca',
          '/templates',
          '/nutricion',
          '/recetas',
          '/suplementos',
          '/habitos',
          '/pagos',
          '/planes',
          '/reportes',
          '/chat',
          '/ajustes',
        },
      );
    });

    test(
        'labels en es-AR: presentes los términos castellanos, ausentes los '
        'ingleses [SCENARIO-751]', () {
      final labels = sidebarRegistry.map((i) => i.label).toSet();

      // Equivalentes en castellano que DEBEN estar.
      for (final esLabel in [
        'Ajustes',
        'Alumnos',
        'Rutinas',
        'Reportes',
        'Pagos',
        'Recetas',
        'Suplementos',
        'Hábitos',
        'Invitaciones',
        'Agenda',
        'Biblioteca',
        'Nutrición',
      ]) {
        expect(labels, contains(esLabel));
      }

      // Equivalentes en inglés que NO deben aparecer.
      for (final enLabel in [
        'Settings',
        'Students',
        'Routines',
        'Reports',
        'Payments',
        'Recipes',
        'Supplements',
        'Habits',
        'Invitations',
        'Schedule',
        'Library',
        'Nutrition',
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
