//
//  WorkoutCloseFeedback.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, tanda de bugfixes de sincronizacion.
//

import Foundation

/// Por que NO se pudo cerrar el entreno.
///
/// Existe porque cerrar podia fallar EN SILENCIO (HANDOFF §8.3):
///
/// - `WorkoutCoordinator.finish()` cortaba con
///   `if !current.pendingSets.isEmpty { return }`. La decision de fondo es
///   correcta —perder series que el atleta hizo es peor que dejarle la pantalla
///   abierta— pero no le avisaba a nadie. El atleta se lesionaba sin señal,
///   tocaba ABANDONAR, confirmaba, el dialogo se cerraba... y la sesion seguia
///   abierta. Cero feedback, y justo en el escenario para el que se agrego el
///   gesto.
/// - El `catch` del cierre en el historial guardaba el error en `syncError`,
///   que **no lo renderizaba ninguna vista**. Contra el telefono, que si
///   ofrece reintentar (`session_player_screen.dart`, `_showFinishError`).
///
/// Es un enum y no un string por la misma razon que `WatchCredentialOutcome`
/// del lado Dart: las dos causas piden lo mismo del atleta —reintentar— pero
/// significan cosas distintas, y colapsarlas esconde la que hay que
/// diagnosticar.
enum WorkoutCloseFailure: Equatable {

    /// Quedan series sin subir. El entreno NO se descarta: se conserva para
    /// reintentar cuando vuelva la señal.
    case seriesSinSubir(Int)

    /// Las series estan arriba, pero el historial no acepto el cierre. La
    /// sesion quedaria `active` en Firestore y el telefono la seguiria
    /// ofreciendo para retomar.
    case historialNoRespondio
}

extension WorkoutCloseFailure {

    /// Lo que se lee en la muñeca.
    ///
    /// Corto a proposito: son 40mm y el atleta lo lee entre series. Dice DOS
    /// cosas y nada mas — que el entreno sigue abierto, y que lo hecho no se
    /// perdio. El detalle tecnico del error se queda en `syncError`, para
    /// diagnostico.
    var mensaje: String {
        switch self {
        case .seriesSinSubir(let cuantas):
            let series = cuantas == 1 ? "1 serie" : "\(cuantas) series"
            return "Falta subir \(series). El entreno sigue abierto."
        case .historialNoRespondio:
            return "No se pudo cerrar. Lo que hiciste está guardado."
        }
    }
}
