//
//  WatchSignedOutPayload.swift
//  TreinoWatch Watch App
//
//  El aviso de que el atleta CERRO SESION en el telefono.
//
//  ── Por que por el MISMO slot que la credencial ─────────────────────────
//
//  El `applicationContext` de salida del telefono es UNO SOLO y se pisa entero.
//  Normalmente eso es una restriccion; para esto es exactamente la semantica
//  que se quiere: publicar este aviso BORRA la credencial del canal.
//
//  Y persiste. `sendMessage` exige que el reloj este alcanzable AHORA, y "la
//  app del reloj esta cerrada" es justo el caso que hay que cubrir: cerrar
//  sesion con el reloj guardado en un cajon tiene que desloguearlo igual. El
//  contexto se entrega en el proximo lanzamiento, con la app cerrada o no.
//
//  ── Por que un `kind` propio y no una credencial vacia ──────────────────
//
//  Mandar el payload de credencial con el `customToken` en blanco NO sirve:
//  `WatchCredentialPayload` valida con `nonEmpty`, el init falla entero, y
//  `handle()` lo descarta en silencio. El telefono creeria que aviso.
//
//  Con un `kind` hermano, ademas, los builds VIEJOS del reloj lo ignoran solos
//  —su guard de credencial no matchea— sin crashear. Forward-compatible.
//
//  Contrato del lado Dart: `lib/features/watch/domain/watch_credential_payload.dart`.
//

import Foundation

enum WatchSignedOutPayload {

    /// Discrimina este aviso de la credencial, que viaja por el mismo slot.
    static let kind = "watchSignedOut"

    /// Si este contexto es el aviso de cierre de sesion.
    ///
    /// Defensivo igual que el resto del puente entre lenguajes: cualquier cosa
    /// que no sea exactamente esto no es un cierre de sesion. Equivocarse para
    /// este lado desloguearia a un atleta que no lo pidio.
    static func esAviso(_ context: [String: Any]) -> Bool {
        (context["kind"] as? String) == kind
    }
}
