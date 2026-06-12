import 'package:flutter/widgets.dart';
import 'package:treino/core/widgets/treino_icon.dart';

import 'sidebar_item.dart';

/// Registro plano de los items del sidebar del Coach Hub web (REQ-CHW-SIDEBAR-001).
///
/// Orden de grupos por [SidebarGroup] (ADR-CHW-002, ODQ-1). En W1.1 es una
/// lista plana; en W1.2 se refactoriza a spreads de cada
/// `sections/<section>/routes.dart`.
///
/// Nota de scope: la enumeración tiene **19 items**. `Solicitudes` (reemplazado
/// por `Actividad`) y `Perfil Público` (Fase W6) están fuera de W1, ver
/// "Out of Scope" del spec. Los `iconBuilder` son tear-offs top-level para que
/// la lista sea `const`.

// RESUMEN
IconData _iconDashboard() => TreinoIcon.sidebarDashboard;
IconData _iconActividad() => TreinoIcon.sidebarActividad;
IconData _iconAgenda() => TreinoIcon.sidebarAgenda;

// ALUMNOS
IconData _iconAlumnos() => TreinoIcon.sidebarAlumnos;
IconData _iconInvitaciones() => TreinoIcon.sidebarInvitaciones;
IconData _iconCuestionario() => TreinoIcon.sidebarCuestionario;

// PLAN
IconData _iconRutinas() => TreinoIcon.sidebarRutinas;
IconData _iconPlanner() => TreinoIcon.sidebarPlanner;
IconData _iconBiblioteca() => TreinoIcon.sidebarBiblioteca;
IconData _iconTemplates() => TreinoIcon.sidebarTemplates;

// WELLNESS
IconData _iconNutricion() => TreinoIcon.sidebarNutricion;
IconData _iconRecetas() => TreinoIcon.sidebarRecetas;
IconData _iconSuplementos() => TreinoIcon.sidebarSuplementos;
IconData _iconHabitos() => TreinoIcon.sidebarHabitos;

// NEGOCIO
IconData _iconPagos() => TreinoIcon.sidebarPagos;
IconData _iconPlanes() => TreinoIcon.sidebarPlanes;
IconData _iconReportes() => TreinoIcon.sidebarReportes;

// COMUNICACIÓN
IconData _iconChat() => TreinoIcon.sidebarChat;

// AJUSTES (bottom)
IconData _iconAjustes() => TreinoIcon.sidebarAjustes;

/// Los 19 items del sidebar, en orden visual. Labels es-AR — `// i18n: Fase W1`.
const List<SidebarItem> sidebarRegistry = [
  // RESUMEN
  SidebarItem(
    id: 'dashboard',
    label: 'Dashboard', // i18n: Fase W1
    route: '/dashboard',
    iconBuilder: _iconDashboard,
    group: SidebarGroup.resumen,
  ),
  SidebarItem(
    id: 'actividad',
    label: 'Actividad', // i18n: Fase W1
    route: '/actividad',
    iconBuilder: _iconActividad,
    group: SidebarGroup.resumen,
  ),
  SidebarItem(
    id: 'agenda',
    label: 'Agenda', // i18n: Fase W1
    route: '/agenda',
    iconBuilder: _iconAgenda,
    group: SidebarGroup.resumen,
  ),

  // ALUMNOS
  SidebarItem(
    id: 'alumnos',
    label: 'Alumnos', // i18n: Fase W1
    route: '/alumnos',
    iconBuilder: _iconAlumnos,
    group: SidebarGroup.alumnos,
  ),
  SidebarItem(
    id: 'invitaciones',
    label: 'Invitaciones', // i18n: Fase W1
    route: '/invitaciones',
    iconBuilder: _iconInvitaciones,
    group: SidebarGroup.alumnos,
  ),
  SidebarItem(
    id: 'cuestionario',
    label: 'Cuestionario', // i18n: Fase W1
    route: '/cuestionario',
    iconBuilder: _iconCuestionario,
    group: SidebarGroup.alumnos,
  ),

  // PLAN
  SidebarItem(
    id: 'rutinas',
    label: 'Rutinas', // i18n: Fase W1
    route: '/rutinas',
    iconBuilder: _iconRutinas,
    group: SidebarGroup.plan,
  ),
  SidebarItem(
    id: 'planner',
    label: 'Planner semanal', // i18n: Fase W1
    route: '/planner',
    iconBuilder: _iconPlanner,
    group: SidebarGroup.plan,
  ),
  SidebarItem(
    id: 'biblioteca',
    label: 'Biblioteca', // i18n: Fase W1
    route: '/biblioteca',
    iconBuilder: _iconBiblioteca,
    group: SidebarGroup.plan,
  ),
  SidebarItem(
    id: 'templates',
    label: 'Templates', // i18n: Fase W1
    route: '/templates',
    iconBuilder: _iconTemplates,
    group: SidebarGroup.plan,
  ),

  // WELLNESS
  SidebarItem(
    id: 'nutricion',
    label: 'Nutrición', // i18n: Fase W1
    route: '/nutricion',
    iconBuilder: _iconNutricion,
    group: SidebarGroup.wellness,
  ),
  SidebarItem(
    id: 'recetas',
    label: 'Recetas', // i18n: Fase W1
    route: '/recetas',
    iconBuilder: _iconRecetas,
    group: SidebarGroup.wellness,
  ),
  SidebarItem(
    id: 'suplementos',
    label: 'Suplementos', // i18n: Fase W1
    route: '/suplementos',
    iconBuilder: _iconSuplementos,
    group: SidebarGroup.wellness,
  ),
  SidebarItem(
    id: 'habitos',
    label: 'Hábitos', // i18n: Fase W1
    route: '/habitos',
    iconBuilder: _iconHabitos,
    group: SidebarGroup.wellness,
  ),

  // NEGOCIO
  SidebarItem(
    id: 'pagos',
    label: 'Pagos', // i18n: Fase W1
    route: '/pagos',
    iconBuilder: _iconPagos,
    group: SidebarGroup.negocio,
  ),
  SidebarItem(
    id: 'planes',
    label: 'Planes comerciales', // i18n: Fase W1
    route: '/planes',
    iconBuilder: _iconPlanes,
    group: SidebarGroup.negocio,
  ),
  SidebarItem(
    id: 'reportes',
    label: 'Reportes', // i18n: Fase W1
    route: '/reportes',
    iconBuilder: _iconReportes,
    group: SidebarGroup.negocio,
  ),

  // COMUNICACIÓN
  SidebarItem(
    id: 'chat',
    label: 'Chat', // i18n: Fase W1
    route: '/chat',
    iconBuilder: _iconChat,
    group: SidebarGroup.comunicacion,
  ),

  // AJUSTES (bottom)
  SidebarItem(
    id: 'ajustes',
    label: 'Ajustes', // i18n: Fase W1
    route: '/ajustes',
    iconBuilder: _iconAjustes,
    group: SidebarGroup.ajustes,
  ),
];
