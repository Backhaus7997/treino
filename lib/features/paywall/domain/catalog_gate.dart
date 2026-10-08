/// La decisión "¿este alumno puede ENTRENAR esta plantilla del catálogo?",
/// como función pura.
///
/// ## Por qué existe separada del provider
///
/// Porque esta regla se escribe DOS VECES: acá en Dart —que sirve al teléfono
/// y al reloj Wear— y en Swift para el reloj de Apple, que no puede usar el SDK
/// de Firestore y habla la REST API. `conformance/README.md` lo dice sin
/// vueltas: *"las mismas reglas escritas dos veces van a divergir. No es una
/// posibilidad, es cuestión de cuándo."*
///
/// Un `Provider` no se puede ejercitar desde un fixture: toma sus entradas de
/// otros providers y devuelve lo que el árbol de Riverpod tenga en ese momento.
/// Esta función toma los tres valores y nada más, así que
/// `conformance/catalog_gate.json` la puede correr caso por caso — y el mismo
/// archivo corre contra la implementación Swift. Si divergen, CI se pone rojo
/// antes de que el alumno vea una plantilla bloqueada en un reloj y libre en el
/// otro.
///
/// El fixture es el contrato; esto es una de sus dos implementaciones.
library;

/// `true` si el candado del catálogo pago frena entrenar esta plantilla.
///
/// ## Los tres estados de [paywallEnforced], y por qué `null` no gatea
///
/// El parámetro es `bool?` y no `bool` porque las dos plataformas tienen un
/// tercer estado real, aunque llegue por caminos distintos:
///
///   • **El teléfono y el Wear** resuelven `AthleteEntitlement`, que es un enum
///     de tres: `entitled` ⇒ `false`, `free` ⇒ `true`, y `unknown` —el read
///     todavía no aterrizó, o falló— ⇒ `null`.
///   • **El reloj de Apple** lee `users/{uid}.athletePaywallEnforced` por REST.
///     El campo puede estar en `true`, en `false`, o **ausente**, que es el
///     estado de hoy en todos los documentos.
///
/// Colapsar eso en un `bool` obligaría a cada plataforma a elegir un default
/// por su cuenta, y ahí es exactamente donde divergirían. Con `null` explícito,
/// el default es parte del contrato: **no se sabe ⇒ no se gatea.**
///
/// Es la misma decisión que ya tomaron las otras dos capas, y las tres tienen
/// que coincidir o el alumno ve un candado que el servidor no aplica:
///   • `AthleteEntitlement.gatesFreeLimits` — `unknown` devuelve `false`.
///   • `firestore.rules`, `paywallEnforcedFor()` — campo ausente ⇒ no aplica.
///
/// Fallar cerrado acá le cortaría el entrenamiento a alguien que paga por un
/// parpadeo de red. En un reloj, con la red del teléfono de por medio, ese caso
/// es mucho más común que en la app. El servidor rebota igual la escritura si
/// no corresponde: client-side es UX, server-side es la ley.
///
/// ## Por qué [isPremium] también es `bool?`
///
/// Por el mismo motivo, del otro lado: el campo puede no estar en el documento.
/// Los docs sembrados antes de que `improved-templates.json` ganara `isPremium`
/// no lo tienen. Ausente ⇒ **gratis**, que replica el `@Default(false)` de
/// `Routine.isPremium` y el `get('isPremium', false)` de `firestore.rules`. Un
/// error de siembra abre, no cobra.
bool catalogGateBlocks({
  required bool paywallEnabled,
  required bool? paywallEnforced,
  required bool? isPremium,
}) {
  // El interruptor maestro primero: apagado, nada de lo demás importa.
  if (!paywallEnabled) return false;
  // `!= true` y no `== false`: cubre el `null` en la misma comparación, y deja
  // escrito que el caso "no se sabe" cae del lado de no gatear.
  if (paywallEnforced != true) return false;
  return isPremium == true;
}
