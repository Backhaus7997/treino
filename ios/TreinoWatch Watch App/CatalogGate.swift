//
//  CatalogGate.swift
//  TreinoWatch Watch App
//
//  El gate del catálogo pago. Ver `docs/paywall-watchos-plan.md`.
//

import Foundation

/// `true` si el candado del catálogo pago frena ENTRENAR esta plantilla.
///
/// ⚠️ **PUERTO LITERAL de `catalogGateBlocks` en
/// `lib/features/paywall/domain/catalog_gate.dart`.** Es la misma regla escrita
/// dos veces: si divergen, el mismo alumno entrena una plantilla en un reloj y
/// no en el otro.
///
/// El contrato está en `conformance/catalog_gate.json` y lo corren los dos
/// lados. Si tocás esto sin tocar el Dart —o al revés— CI se pone rojo.
///
/// ─── Los tres estados de `paywallEnforced`, y por qué `nil` NO gatea ───
///
/// El parámetro es `Bool?` y no `Bool` porque las dos plataformas tienen un
/// tercer estado real, aunque llegue por caminos distintos:
///
///   • **El teléfono y el Wear** resuelven `AthleteEntitlement`, un enum de
///     tres: `entitled` ⇒ `false`, `free` ⇒ `true`, y `unknown` —el read
///     todavía no aterrizó, o falló— ⇒ `nil`.
///   • **Este reloj** lee `users/{uid}.athletePaywallEnforced` por REST. El
///     campo puede estar en `true`, en `false`, o **ausente**, que es el estado
///     de HOY en todos los documentos.
///
/// Colapsar eso en un `Bool` obligaría a cada plataforma a elegir un default
/// por su cuenta, y ahí es exactamente donde divergirían. Con `nil` explícito,
/// el default es parte del contrato: **no se sabe ⇒ no se gatea.**
///
/// ─── Por qué fallar ABIERTO, y por qué acá pesa más que en el teléfono ───
///
/// Fallar cerrado le cortaría el entrenamiento a alguien que paga, por un
/// parpadeo de red. En un reloj —con la red del teléfono de por medio y una
/// batería que apaga la radio— ese caso es mucho más común que en la app.
///
/// Y no afloja nada: el servidor rebota igual la escritura si no corresponde.
/// La regla de `firestore.rules` sobre `sessions` es la ley; esto es UX.
///
/// Es la misma decisión que ya tomaron las otras capas, y las cuatro tienen que
/// coincidir o el alumno ve un candado que el servidor no aplica:
///   • `AthleteEntitlement.gatesFreeLimits` — `unknown` devuelve `false`.
///   • `firestore.rules`, `paywallEnforcedFor()` — campo ausente ⇒ no aplica.
///   • el gate del Wear.
///
/// ─── Por qué `isPremium` también es `Bool?` ───
///
/// Por el mismo motivo, del otro lado: el campo puede no estar en el documento.
/// Los docs sembrados antes de que `improved-templates.json` ganara `isPremium`
/// no lo tienen. Ausente ⇒ **gratis**, que replica el `@Default(false)` de
/// `Routine.isPremium` y el `get('isPremium', false)` de `firestore.rules`. Un
/// error de siembra abre, no cobra.
///
/// ─── Lo que esta función NO hace ───
///
/// **No gatea el cierre de un entreno.** La regla del servidor gatea sólo el
/// `create` de `sessions`, a propósito: cerrar un entreno que ya existe no
/// puede depender de un derecho que se pudo vencer en el medio, o se le borra
/// un entrenamiento que la persona de verdad hizo. Llamar a esto desde un
/// camino de `finish` rompería esa asimetría.
func catalogGateBlocks(
    paywallEnabled: Bool,
    paywallEnforced: Bool?,
    isPremium: Bool?
) -> Bool {
    // El interruptor maestro primero: apagado, nada de lo demás importa.
    if !paywallEnabled { return false }
    // `!= true` y no `== false`: cubre el `nil` en la misma comparación, y deja
    // escrito que el caso "no se sabe" cae del lado de no gatear.
    if paywallEnforced != true { return false }
    return isPremium == true
}

/// El gate del catálogo pago, listo para llamar desde un punto de arranque.
///
/// ─── Una función, no un `if` copiado ───
///
/// Son dos puntos de arranque hoy —el "Empezar" de HOY y el de la lista— y van
/// a ser más. `docs/paywall-watchos-plan.md` §4.3 lo pide explícito: *"No
/// copies el gate en cada call site. Una función, dos llamadas — es lo que
/// hace que el fixture sirva de algo."*
enum CatalogGate {

    /// Lo que se le muestra al atleta cuando la plantilla está bloqueada.
    ///
    /// Nombra **el teléfono** a propósito. El checkout no existe en el reloj y
    /// no va a existir: mandarlo a "ver el plan" acá sería prometerle una
    /// salida que esta pantalla no tiene.
    ///
    /// Es el espejo de `WearStrings.plantillaPaga` del lado Wear. Que los dos
    /// relojes digan lo mismo no es cosmética: un atleta con los dos ve el
    /// mismo producto.
    static let mensajeBloqueado = """
    Esta plantilla es del plan pago.
    Mirala en el teléfono.
    """

    /// ¿Hay que frenar este entreno?
    ///
    /// **La decisión SIEMPRE pasa por `catalogGateBlocks`**, la función bajo
    /// contrato de conformidad. Lo único que hace este envoltorio es conseguir
    /// el tercer dato —la conclusión del servidor— y evitar ir a buscarlo
    /// cuando no hace falta.
    ///
    /// Ese corto-circuito es de RED, no de lógica: con el flag apagado o con
    /// una plantilla gratis, `catalogGateBlocks` devuelve `false` para
    /// CUALQUIER valor de `paywallEnforced` —es una propiedad del contrato, y
    /// los casos del fixture la fijan— así que leer el documento sería pagar
    /// una ronda de red para llegar al mismo lugar.
    ///
    /// Por eso no hay dos caminos de decisión: hay uno, y a veces se le pasa
    /// `nil` porque el valor real es irrelevante.
    static func blocks(
        workout: TodaysWorkout,
        client: FirestoreREST,
        uid: String
    ) async -> Bool {
        let enforced: Bool?
        if kAthletePaywallEnabled && workout.isPremium {
            enforced = await PaywallEntitlement.shared.enforced(
                client: client, uid: uid
            )
        } else {
            enforced = nil
        }

        return catalogGateBlocks(
            paywallEnabled: kAthletePaywallEnabled,
            paywallEnforced: enforced,
            isPremium: workout.isPremium
        )
    }
}
