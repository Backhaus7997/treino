//
//  CatalogGateWiring.swift
//  TreinoWatch Watch App
//
//  El envoltorio que conecta el gate puro con la app.
//
//  ⚠️ Vive SEPARADO de `CatalogGate.swift` a propósito: ese archivo lo compila
//  `conformance/run_swift.sh` sin la app —sin SwiftUI, sin Firestore— para
//  poder ejercitar el contrato compartido en CI sobre ubuntu. Todo lo que
//  dependa de tipos de la app tiene que estar de ESTE lado, o el job se pone
//  rojo con `cannot find type ... in scope`.
//

import Foundation

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
