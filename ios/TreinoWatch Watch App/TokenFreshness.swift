//
//  TokenFreshness.swift
//  TreinoWatch Watch App
//
//  Cuando hay que renovar el idToken de Firebase.
//
//  ── Por que existe ──────────────────────────────────────────────────────
//
//  `freshIdToken()` renovaba INCONDICIONALMENTE: un POST completo a
//  securetoken.googleapis.com delante de CADA sincronizacion. El comentario
//  decia "la renovacion es barata comparada con manejar expiracion a mano y
//  equivocarse" — razonable en una app de telefono, caro en una muneca.
//
//  Medido: marcar una serie en el reloj disparaba 4 viajes de red EN SERIE
//  antes de que la serie existiera en Firestore, y este era el PRIMERO de los
//  cuatro. El atleta lo reporto como "tarda mucho en verse en el telefono".
//
//  El idToken dura 3600 segundos. Renovarlo por cada serie es tirar un viaje
//  entero de radio, que en un reloj es lo mas caro que hay.
//
//  La regla vive aparte y pura para poder medirla en el host, que es donde el
//  reloj no llega.
//

import Foundation

enum TokenFreshness {

    /// Cuanto se considera valido un idToken, con margen.
    ///
    /// Firebase los emite con `expires_in` 3600. Se usan 3000 para dejar diez
    /// minutos de colchon: un entreno largo no puede quedar a merced de un
    /// token que vence entre que se decide usarlo y que llega la request.
    static let ttl: TimeInterval = 3000

    /// Si hay que pedir uno nuevo.
    ///
    /// Sin token cacheado, siempre. El `emitidoEn` en el futuro tambien fuerza
    /// renovacion: un reloj con la hora corrida no puede quedarse con un token
    /// eterno.
    static func shouldRefresh(
        emitidoEn: Date?,
        ahora: Date,
        ttl: TimeInterval = TokenFreshness.ttl
    ) -> Bool {
        guard let emitidoEn else { return true }
        let edad = ahora.timeIntervalSince(emitidoEn)
        if edad < 0 { return true }
        return edad >= ttl
    }
}
