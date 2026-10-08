/// Elige QUÉ rutina es la activa del atleta.
///
/// Extraído de `todaysRoutineProvider` para que la regla sea:
///   1. testeable como función pura, sin levantar un ProviderContainer, y
///   2. **replicable byte a byte por el cliente watchOS**, que la reimplementa
///      en Swift. Los fixtures de `conformance/routine_selection.json` son el
///      contrato entre ambas — si divergen, teléfono y reloj le muestran
///      rutinas DISTINTAS al mismo usuario.
///
/// Trabaja sobre ids y no sobre objetos `Routine` a propósito: la regla es de
/// identidad, no de contenido, y así el contrato es portable a Swift sin
/// arrastrar el modelo entero.
///
/// PRIORIDAD (decision log 2026-06-18, workout redesign slice 1):
///
/// 0. Marcador explícito `UserProfile.activeRoutineId`, resuelto contra la
///    lista UNIFICADA: primero las asignadas por PF, después las auto-creadas,
///    y por último las plantillas del catálogo que el atleta eligió seguir.
///    Un id obsoleto (rutina archivada o borrada) cae al resto de la cadena.
/// 1. Plan asignado por un PF. Si hay varios gana el más nuevo — el repo ya
///    los ordena por `createdAt` descendente.
/// 2. Una sola rutina auto-creada: se auto-activa, no hace falta marcador.
/// 3. Varias auto-creadas: exige marcador explícito.
/// 4. Null — multi-rutina sin marcador. El home cae al CTA vacío.
///
/// El catálogo NO tiene tier propio a propósito: seguir una plantilla es
/// siempre una decisión explícita del atleta, y auto-activar una del montón
/// sería elegir por él entre siete opciones que no pidió.
///
/// [assignedIds] y [selfCreatedIds] llegan ordenados como los devuelve el
/// repositorio (más nuevo primero).
///
/// [catalogIds] son las plantillas del sistema (`source == 'system'`) que el
/// atleta puede estar SIGUIENDO sin haberlas copiado. Sólo participan del tier
/// 0: una plantilla del catálogo nunca se auto-activa, hay que elegirla — por
/// eso no entra en los tiers 1-3.
///
/// El llamador puede pasar `const []` cuando ya sabe que no hace falta
/// resolverla —marcador nulo, o marcador que ya matcheó contra las otras dos
/// listas— y ahorrarse la lectura. Eso NO cambia el resultado: en los dos
/// casos el catálogo no se hubiera consultado igual. Es la optimización que
/// evita una query extra por sync en el reloj y una lectura extra en la Home.
String? resolveActiveRoutineId({
  required String? activeRoutineId,
  required List<String> assignedIds,
  required List<String> selfCreatedIds,
  List<String> catalogIds = const [],
}) {
  // Tier 0 — marcador explícito, buscado en las tres listas.
  if (activeRoutineId != null && activeRoutineId.isNotEmpty) {
    if (assignedIds.contains(activeRoutineId)) return activeRoutineId;
    if (selfCreatedIds.contains(activeRoutineId)) return activeRoutineId;
    if (catalogIds.contains(activeRoutineId)) return activeRoutineId;
    // Id obsoleto: sigue la cadena en vez de devolver null.
  }

  // Tier 1 — plan de PF.
  if (assignedIds.isNotEmpty) return assignedIds.first;

  // Tier 2 — única auto-creada.
  if (selfCreatedIds.length == 1) return selfCreatedIds.first;

  // Tier 3 — varias auto-creadas: requiere marcador. Llegar acá implica que el
  // marcador era null u obsoleto (si hubiera sido válido, el tier 0 ya lo
  // habría devuelto), así que el resultado es siempre null. Se deja explícito
  // en vez de colapsarlo con el tier 4 porque son razones distintas: acá HAY
  // rutinas y falta elegir; abajo no hay ninguna.
  //
  // Tier 4 — sin rutinas.
  return null;
}
