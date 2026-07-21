import 'package:treino/features/coach_hub/presentation/sections/agenda/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/perfil_publico/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routes.dart';

import 'sidebar_item.dart';

/// Registro de los items del sidebar del Coach Hub web (REQ-CHW-SIDEBAR-001).
///
/// Agregador data-driven (ADR-CHW-002): cada `sections/<section>/routes.dart`
/// posee su propio `<section>SidebarItems`; acá se concatenan vía spreads. El
/// **orden de los spreads fija el orden visual** dentro de cada grupo
/// ([SidebarGroup], ODQ-1) — por eso se listan en orden de pantalla, no
/// alfabético. Este archivo es el único punto de conflicto al agregar secciones
/// en W2+, y se resuelve con merge aditivo.
///
/// **W2 reduce 2026-07-02**: el sidebar pasó de ~19 items a 7. Los items
/// removidos (Actividad, Invitaciones, Cuestionario, Planner, Templates,
/// Nutrición, Recetas, Suplementos, Hábitos, Planes comerciales) duplicaban
/// funcionalidad del `alumno_detail` (por-alumno) o pertenecen a una futura
/// Biblioteca (sub-tabs). Sus screens y rutas siguen existiendo (los routes
/// se registran en `coach_hub_router.dart` por section); solo no aparecen en
/// el sidebar. Para exponerlos de vuelta basta con re-importar el
/// `<section>SidebarItems` acá.
///
/// **Rutinas re-agregado (editor web)**: Rutinas volvió al grupo RECURSOS como
/// punto de entrada del editor de rutinas web (elegí alumno → editor), llevando
/// el total a 8. Mismo flujo que mobile ("Asignar rutina"), expuesto también
/// desde el menú lateral.
///
/// **Solicitudes re-agregado (Fase 4 WU-06, ADR-F4-04)**: Invitaciones
/// (copia de usuario "Solicitudes") vuelve al grupo GESTIÓN, inmediatamente
/// después de Alumnos, con badge real de pendientes
/// (`invitacionesPendingCountProvider`) — llevando el total a 9.
/// Re-exposición parcial de la reducción W2, justificada porque Fase 4
/// entrega la bandeja real (antes era `ProximamenteScreen`). Nota: el
/// registro deja de ser `const` (pasa a `final`) porque
/// `invitacionesSidebarItems` tampoco lo es — su `badgeProvider` referencia
/// un provider real, no evaluable en tiempo de compilación.
///
/// **Nutrición re-agregada (Fase 6 WU-06, ADR-F6-07)**: la overview
/// cross-alumno de planes (Fase 6 WU-04, antes solo alcanzable por URL
/// directa) vuelve al grupo RECURSOS, inmediatamente después de Biblioteca
/// — simetría con la re-exposición de Solicitudes en ADR-F4-04 — llevando
/// el total a 10.
///
/// **Perfil público agregado (Fase 11 WU-01, ADR-F11-01)**: nueva sección
/// que muestra al PF cómo lo ven los alumnos potenciales en TREINO Coach
/// Discovery; se agrega al grupo GESTIÓN inmediatamente después de Chat
/// (adyacente, sin header nuevo) — llevando el total a 11.
final List<SidebarItem> sidebarRegistry = [
  // GESTIÓN — surfaces multi-alumno del día a día del PF
  ...dashboardSidebarItems,
  ...alumnosSidebarItems,
  ...invitacionesSidebarItems,
  ...agendaSidebarItems,
  ...chatSidebarItems,
  ...perfilPublicoSidebarItems,

  // RECURSOS — bibliotecas del PF y finanzas
  ...bibliotecaSidebarItems,
  ...nutricionSidebarItems,
  ...rutinasSidebarItems,
  ...pagosSidebarItems,

  // AJUSTES (pinneado al fondo, fuera de grupo visual)
  ...ajustesSidebarItems,
];

/// Devuelve el [SidebarItem] de `sidebarRegistry` cuya `route` matchea
/// [location] (exacta o como prefijo `route/...`), o `null` si ninguna
/// matchea. Misma regla de "activo" que usa el sidebar para resaltar el
/// ítem; el top bar la reusa para el título de sección (REQ-SH-007).
SidebarItem? activeSidebarItem(String location) {
  for (final item in sidebarRegistry) {
    if (location == item.route || location.startsWith('${item.route}/')) {
      return item;
    }
  }
  return null;
}
