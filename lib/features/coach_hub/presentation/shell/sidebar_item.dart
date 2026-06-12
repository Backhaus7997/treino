import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Grupo lógico de un [SidebarItem] en el sidebar del Coach Hub web.
///
/// El orden de declaración fija el orden visual de los headers (ADR-CHW-002,
/// ODQ-1). `ajustes` no se renderiza como header de grupo: su único ítem va
/// pinneado al fondo del sidebar.
enum SidebarGroup {
  resumen,
  alumnos,
  plan,
  wellness,
  negocio,
  comunicacion,
  ajustes;

  /// Etiqueta del header de grupo en es-AR Rioplatense.
  String get label {
    switch (this) {
      case SidebarGroup.resumen:
        return 'RESUMEN'; // i18n: Fase W1
      case SidebarGroup.alumnos:
        return 'ALUMNOS'; // i18n: Fase W1
      case SidebarGroup.plan:
        return 'PLAN'; // i18n: Fase W1
      case SidebarGroup.wellness:
        return 'WELLNESS'; // i18n: Fase W1
      case SidebarGroup.negocio:
        return 'NEGOCIO'; // i18n: Fase W1
      case SidebarGroup.comunicacion:
        return 'COMUNICACIÓN'; // i18n: Fase W1
      case SidebarGroup.ajustes:
        return 'AJUSTES'; // i18n: Fase W1
    }
  }
}

/// Descriptor inmutable de un ítem del sidebar (ADR-CHW-002).
///
/// Cada sección del Coach Hub aporta sus propios items desde
/// `sections/<section>/routes.dart`; el shell los concatena en
/// `sidebar_registry.dart`. `@immutable` + `const` constructor — sin freezed.
@immutable
class SidebarItem {
  const SidebarItem({
    required this.id,
    required this.label,
    required this.route,
    required this.iconBuilder,
    required this.group,
    this.badgeProvider,
  });

  /// Identificador estable en kebab-case (eg. `dashboard`, `alumnos`).
  final String id;

  /// Etiqueta de display en es-AR.
  final String label;

  /// Ruta go_router (eg. `/dashboard`).
  final String route;

  /// Builder lazy del ícono — permite acceder a `TreinoIcon.*` sin `context`.
  final IconData Function() iconBuilder;

  /// Grupo al que pertenece el ítem.
  final SidebarGroup group;

  /// Provider opcional del contador de badge. En W1 todos los items pasan
  /// `null`; el wiring real llega en fases posteriores.
  final ProviderListenable<int?>? badgeProvider;
}
