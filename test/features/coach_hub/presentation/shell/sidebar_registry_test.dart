import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_item.dart';
import 'package:treino/features/coach_hub/presentation/shell/sidebar_registry.dart';

void main() {
  group('sidebarRegistry (REQ-CHW-SIDEBAR-001)', () {
    test(
        'tiene exactamente 11 items (7 post-W2 reduce + Rutinas + Solicitudes '
        '+ Nutrición + Perfil público + Moderación): Dashboard, Alumnos, '
        'Solicitudes, Agenda, Chat, Perfil público, Biblioteca, Nutrición, '
        'Rutinas, Pagos, Moderación', () {
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
      //
      // Fase 11 WU-01 (ADR-F11-01): Perfil público se agrega al grupo
      // GESTIÓN, inmediatamente después de Chat — llevando el total de 9 a 10.
      // (Este párrafo decía «de 10 a 11» y era falso: la aserción era 10 y los
      // items enumerados, diez. Un número equivocado al lado del que manda es
      // exactamente lo que hace dudar del que manda.)
      //
      // Moderación se agrega al grupo CUENTA — llevando el total de 10 a 11.
      // Es la primera superficie de STAFF del hub: vive en el registry como
      // cualquier otro item, pero su `visibleProvider` la esconde de todo el
      // que no tenga el claim `moderator`. Para un entrenador el sidebar sigue
      // teniendo diez.
      expect(sidebarRegistry.length, 11);
    });

    test('cubre los grupos activos post-reduce, cada uno no vacío', () {
      // CUENTA volvió a tener un item —Moderación— pero NO se lista acá: para
      // un entrenador sigue vacío, porque el único que tiene se filtra por
      // `visibleProvider`. El widget además lo saltea por `items.isNotEmpty`,
      // así que el header no se dibuja.
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

    test('los grupos legacy quedan sin items en el registry', () {
      // El enum los mantiene para que items futuros no rompan la firma;
      // el registry no los referencia post-reduce.
      //
      // CUENTA salió de esta lista: volvió a tener un item, «Moderación». No es
      // un retroceso del reduce —lo que se removió ahí fue «Reportes», una
      // sección de negocio sin scope— sino una superficie de STAFF, que además
      // sólo se le renderiza a quien tiene el claim `moderator`. Para un
      // entrenador el grupo sigue sin existir.
      const emptyGroups = [
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

    test('el grupo ajustes no agrega un segundo acceso a cuenta', () {
      final ajustes =
          sidebarRegistry.where((i) => i.group == SidebarGroup.ajustes);
      expect(ajustes, isEmpty);
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
          '/perfil-publico',
          '/biblioteca',
          '/nutricion',
          '/rutinas',
          '/pagos',
          // Staff. Sólo se renderiza con el claim `moderator` (ver
          // `moderacionSidebarItems.visibleProvider`), pero vive en el registry
          // como cualquier otro: el filtro de visibilidad corre DESPUES, en el
          // sidebar. Si esta ruta desapareciera de acá, el item no existiria
          // para nadie.
          '/moderacion',
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
        [
          'dashboard',
          'alumnos',
          'invitaciones',
          'agenda',
          'chat',
          'perfil-publico',
        ],
      );
    });

    test(
        'labels en es-AR: presentes los términos castellanos, ausentes los '
        'ingleses [SCENARIO-751]', () {
      final labels = sidebarRegistry.map((i) => i.label).toSet();

      // Equivalentes en castellano que DEBEN estar (subset post-reduce).
      for (final esLabel in [
        'Alumnos',
        'Solicitudes',
        'Pagos',
        'Agenda',
        'Biblioteca',
        'Chat',
        'Dashboard',
        'Nutrición',
        'Perfil público',
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

    test('la metadata de /ajustes sigue titulando el top bar', () {
      final item = activeSidebarItem('/ajustes');
      expect(item?.id, 'cuenta');
      expect(item?.label, 'Mi cuenta');
    });

    test('cada iconBuilder devuelve un IconData no nulo', () {
      for (final item in sidebarRegistry) {
        expect(item.iconBuilder(), isA<IconData>());
      }
    });

    test(
        'Solicitudes (fase 4, ADR-F4-04) y Pagos (fase 9, WU-08) exponen '
        'badgeProvider; el resto sigue sin badge', () {
      const withBadge = {'invitaciones', 'pagos'};
      for (final item in sidebarRegistry) {
        if (withBadge.contains(item.id)) {
          expect(
            item.badgeProvider,
            isNotNull,
            reason: '${item.id} cablea su badgeProvider real',
          );
        } else {
          expect(item.badgeProvider, isNull);
        }
      }
    });
  });
}
