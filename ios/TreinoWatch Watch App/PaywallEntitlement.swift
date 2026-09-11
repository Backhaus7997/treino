//
//  PaywallEntitlement.swift
//  TreinoWatch Watch App
//
//  De dónde saca el reloj si el candado del catálogo pago le aplica al atleta.
//  Ver `docs/paywall-watchos-plan.md` §2.2.
//

import Foundation

/// El interruptor maestro del paywall del alumno.
///
/// ⚠️ **TIENE QUE VALER LO MISMO que `kAthletePaywallEnabled` en
/// `lib/features/paywall/domain/athlete_entitlement.dart`.**
///
/// Son dos constantes en dos lenguajes, y por lo tanto pueden divergir. Contra
/// eso hay un test —`test/conformance/paywall_flag_parity_test.dart`— que lee
/// ESTE archivo y el Dart, y se pone rojo si no coinciden. Si lo prendés de un
/// lado y te olvidás del otro, CI te lo dice antes de que un atleta con reloj
/// vea un candado que el teléfono no le muestra.
///
/// El orden para encenderlo está en `docs/paywall-watchos-plan.md` §5, y no es
/// arbitrario: **primero el servidor, después el cliente**. Al revés, el
/// cliente gatea cosas que el servidor todavía permite.
let kAthletePaywallEnabled = false

/// Lee y cachea `users/{uid}.athletePaywallEnforced`.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ ESTE CAMPO Y NO EL CRUCE QUE HACE EL TELÉFONO
/// ═══════════════════════════════════════════════════════════════════════════
///
/// El teléfono cruza DOS fuentes —`athleteSubscription` **o** un vínculo con un
/// PF activo— porque puede: tiene el SDK y los providers.
///
/// El reloj no puede resolver `trainer_links`: los ids son autogenerados, así
/// que por REST eso es una query más y otra ronda de red **en el camino crítico
/// de tocar "Empezar"**.
///
/// `athletePaywallEnforced` es exactamente la conclusión ya cruzada de esas dos
/// fuentes, escrita por la Cloud Function, y es el MISMO campo que lee
/// `firestore.rules`. Un solo `get`, y el reloj coincide con el servidor por
/// construcción.
///
/// **La trampa que esto evita**: si el reloj resolviera el entitlement por su
/// cuenta y se equivocara para el otro lado, le cortaría el entrenamiento a
/// alguien que paga. Leyendo la misma conclusión que la regla, el gate del
/// reloj no puede ser MÁS ESTRICTO que el servidor.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ FALLA ABIERTO, SIEMPRE
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Cualquier problema —red, timeout, 403, documento ausente, campo ausente—
/// devuelve `nil`, y `catalogGateBlocks` define `nil` como "no se sabe ⇒ no se
/// gatea".
///
/// No es pereza: en un reloj, con la red del teléfono de por medio y una
/// batería que apaga la radio, ese caso es mucho MÁS común que en la app.
/// Fallar cerrado le cortaría el entrenamiento a alguien que paga por un
/// parpadeo.
///
/// Y no afloja nada: la regla de `firestore.rules` sobre `sessions` rebota
/// igual la escritura si no corresponde. Client-side es UX; server-side es la
/// ley.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ SE CACHEA, Y POR QUÉ SÓLO EN MEMORIA
/// ═══════════════════════════════════════════════════════════════════════════
///
/// El camino crítico es un tap en un reloj. Pagar una ronda de red extra cada
/// vez que alguien toca "Empezar" se siente, y este dato casi no cambia.
///
/// El caché vive en memoria y muere con el proceso, a propósito: persistirlo
/// significaría que un alumno que dejó de pagar sigue entrenando plantillas
/// pagas hasta que alguien invalide el disco. Que se pierda al cerrar la app
/// es la invalidación más barata y la más difícil de arruinar.
///
/// ⚠️ **Consecuencia consciente**: un alumno que paga MIENTRAS la app del reloj
/// está abierta sigue viendo el candado hasta que la cierre. Es el lado
/// correcto del error —le sobra candado, no le falta— y el checkout no existe
/// en el reloj de todos modos: para pagar tuvo que ir al teléfono.
actor PaywallEntitlement {
    static let shared = PaywallEntitlement()

    private var cache: [String: Bool?] = [:]

    /// La conclusión del servidor para [uid], o `nil` si no se pudo saber.
    ///
    /// El tipo de retorno es `Bool?` y el caché guarda `Bool?`: se cachea
    /// también el "no se sabe" del campo AUSENTE, que es el estado de hoy en
    /// todos los documentos y sería absurdo re-preguntarlo en cada tap.
    ///
    /// Lo que NO se cachea es el FALLO: si la lectura tira, no se guarda nada y
    /// el próximo intento vuelve a preguntar. Cachear un error de red dejaría
    /// al atleta sin gate —o con gate— por el resto de la sesión de app, por un
    /// parpadeo.
    func enforced(client: FirestoreREST, uid: String) async -> Bool? {
        if let cached = cache[uid] { return cached }

        do {
            let fields = try await client.document("users/\(uid)")
            // Documento ausente ⇒ nil. Campo ausente ⇒ nil. Los dos son
            // "no se sabe", y los dos se cachean.
            let valor = FS.bool(fields?["athletePaywallEnforced"])
            cache[uid] = valor
            return valor
        } catch {
            // No se cachea. Ver el dartdoc de arriba.
            return nil
        }
    }

    /// Borra el caché. Para el logout, y para los tests.
    func reset() {
        cache.removeAll()
    }
}
