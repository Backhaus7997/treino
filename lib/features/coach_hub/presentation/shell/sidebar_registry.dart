import 'package:treino/features/coach_hub/presentation/sections/agenda/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/routes.dart';
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
const List<SidebarItem> sidebarRegistry = [
  // GESTIÓN — surfaces multi-alumno del día a día del PF
  ...dashboardSidebarItems,
  ...alumnosSidebarItems,
  ...agendaSidebarItems,
  ...chatSidebarItems,

  // RECURSOS — bibliotecas del PF y finanzas
  ...bibliotecaSidebarItems,
  ...rutinasSidebarItems,
  ...pagosSidebarItems,

  // AJUSTES (pinneado al fondo, fuera de grupo visual)
  ...ajustesSidebarItems,
];
