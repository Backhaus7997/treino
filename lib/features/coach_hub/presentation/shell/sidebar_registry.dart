import 'package:treino/features/coach_hub/presentation/sections/actividad/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/cuestionario/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/habitos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/planner/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/recetas/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/reportes/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/suplementos/routes.dart';
import 'package:treino/features/coach_hub/presentation/sections/templates/routes.dart';

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
/// Nota de scope: la enumeración tiene **19 items**. `Solicitudes` (reemplazado
/// por `Actividad`) y `Perfil Público` (Fase W6) están fuera de W1, ver
/// "Out of Scope" del spec. `legacy/routes.dart` (`/upload-plan`) aporta rutas
/// pero NO items de sidebar.
const List<SidebarItem> sidebarRegistry = [
  // RESUMEN
  ...dashboardSidebarItems,
  ...actividadSidebarItems,
  ...agendaSidebarItems,

  // ALUMNOS
  ...alumnosSidebarItems,
  ...invitacionesSidebarItems,
  ...cuestionarioSidebarItems,

  // PLAN
  ...rutinasSidebarItems,
  ...plannerSidebarItems,
  ...bibliotecaSidebarItems,
  ...templatesSidebarItems,

  // WELLNESS
  ...nutricionSidebarItems,
  ...recetasSidebarItems,
  ...suplementosSidebarItems,
  ...habitosSidebarItems,

  // NEGOCIO
  ...pagosSidebarItems,
  ...planesSidebarItems,
  ...reportesSidebarItems,

  // COMUNICACIÓN
  ...chatSidebarItems,

  // AJUSTES (bottom)
  ...ajustesSidebarItems,
];
