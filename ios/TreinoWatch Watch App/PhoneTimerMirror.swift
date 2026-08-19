//
//  PhoneTimerMirror.swift
//  TreinoWatch Watch App
//
//  El cronometro que arranco en el TELEFONO, espejado en la muneca.
//
//  ── Por que ESPEJAR y no adoptar ────────────────────────────────────────
//
//  El lado que arranca el cronometro es el DUENO de la serie; el otro la
//  muestra y no la carga.
//
//  Si el reloj adoptara la orden como cronometro propio, al llegar a cero
//  llamaria a `logSet` — y el telefono tambien, porque el la arranco. Dos
//  documentos para la misma serie, que es exactamente el problema que ya
//  describe `WatchNudgeService.reasonSetLogged` del lado Dart: los dos clientes
//  generan ids distintos, asi que el que llega tarde no puede deduplicar.
//
//  Por eso este espejo NO tiene camino a `logSet`. Es una pantalla, nada mas.
//
//  ── Por que llega por MENSAJE ───────────────────────────────────────────
//
//  El `applicationContext` de entrada esta ocupado por la credencial del reloj,
//  y es UNO SOLO: mandar el cronometro por ahi la pisaria y dejaria al reloj sin
//  poder hablar con Firestore. `sendMessage` es transitorio y no toca el
//  contexto persistido. El precio es que exige alcanzabilidad: con la app del
//  reloj cerrada la orden se pierde, en silencio y a proposito.
//
//  Contrato del lado Dart: `lib/features/watch/domain/watch_timer_command.dart`.
//  La aritmetica de la cuenta es compartida y vive en `CountdownRules`, bajo
//  contrato en `conformance/duration_timer.json`.
//

import Foundation

/// Un cronometro corriendo en el telefono.
struct PhoneTimer: Equatable {
    let exerciseId: String
    let setNumber: Int
    let totalSeconds: Int
    /// Instante de fin. Viaja el FIN y no lo que falta, asi los dos lados
    /// derivan la misma cuenta contra su propio reloj de pared.
    let endsAt: Date
}

enum PhoneTimerMirror {

    /// Discrimina esta orden de cualquier otra que viaje por el mismo canal.
    ///
    /// El canal lo comparte con el aviso de "relee" (`watchRefresh`): sin este
    /// campo el reloj trataria un cronometro como un pedido de recarga.
    static let kind = "watchTimer"

    enum Command: Equatable {
        case start(PhoneTimer)
        case cancel
    }

    /// Un instante a partir de milisegundos desde epoch.
    ///
    /// El parametro es `Int64` y NO `Int`, y no es cosmetico: watchOS corre
    /// arm64_32, donde `Int` es de 32 bits. Los milisegundos desde 1970 rondan
    /// 1,8e12 y exceden el maximo de Int32 por un factor de ~832.
    static func fecha(desdeMs ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    /// Canario de 32 bits. **No borrar, aunque parezca que no lo usa nadie.**
    ///
    /// Amarra la firma de `fecha(desdeMs:)` a 64 bits: si alguien le cambia el
    /// parametro a `Int`, esta asignacion deja de compilar y
    /// `scripts/typecheck_watch.sh` se pone rojo.
    ///
    /// Existe porque es la unica proteccion automatica que hay para esto. Los
    /// tests puros del reloj corren en el HOST, arm64 de 64 bits, donde el
    /// codigo con `Int` es correcto — son estructuralmente incapaces de
    /// reproducir un desborde de 32 bits. Es el bug que crasheaba el reloj en el
    /// primer dato de pulso (commit 3a0840cc).
    ///
    /// Es un canario de TIPO y no un literal grande, y la diferencia se midio:
    /// `swiftc -typecheck` NO diagnostica desborde de literales enteros. Ni
    /// siquiera con `Int32` explicito — calibrado contra ese control, que se
    /// sabia que tenia que fallar. Ese diagnostico recien aparece compilando de
    /// verdad (`-c`), y este script no compila. Un desajuste de tipos, en
    /// cambio, lo agarra siempre.
    private static let canario32Bits: (Int64) -> Date = fecha(desdeMs:)

    /// Lee un mensaje entrante, o devuelve nil si no es una orden de cronometro.
    ///
    /// Defensivo a proposito: el payload cruza un puente entre lenguajes y un
    /// cambio del lado Dart no puede tirar la app del reloj.
    static func parse(_ message: [String: Any]) -> Command? {
        guard message["kind"] as? String == kind else { return nil }

        switch message["action"] as? String {
        case "cancel":
            return .cancel

        case "start":
            // La anotacion `Int64` es parte de la proteccion: si alguien
            // reemplaza `int64(...)` por `as? Int`, esto deja de compilar en
            // vez de fallar en silencio en la muneca.
            guard
                let exerciseId = message["exerciseId"] as? String,
                !exerciseId.isEmpty,
                let setNumber = message["setNumber"] as? Int, setNumber > 0,
                let totalSeconds = message["totalSeconds"] as? Int, totalSeconds > 0,
                let endsAtMs: Int64 = int64(message["endsAtMs"])
            else { return nil }

            return .start(
                PhoneTimer(
                    exerciseId: exerciseId,
                    setNumber: setNumber,
                    totalSeconds: totalSeconds,
                    endsAt: fecha(desdeMs: endsAtMs)
                )
            )

        default:
            return nil
        }
    }

    /// Si una orden de arranque todavia vale la pena mostrarla.
    ///
    /// Una orden puede llegar TARDE: `sendMessage` exige alcanzabilidad, y el
    /// sistema puede entregarla al reconectar. Para entonces la serie ya
    /// termino, y una cuenta vencida tomando la pantalla es peor que no mostrar
    /// nada — el atleta ya esta en otra.
    ///
    /// Usa la misma regla que la cuenta, que esta bajo contrato compartido con
    /// el telefono en `conformance/duration_timer.json`.
    static func shouldShow(_ timer: PhoneTimer, now: Date) -> Bool {
        !CountdownRules.isFinished(endsAt: timer.endsAt, now: now)
    }

    /// Lee un entero de 64 bits de un payload de WatchConnectivity.
    ///
    /// `as? Int` NO sirve: en arm64_32 devuelve nil para cualquier timestamp en
    /// milisegundos, y el cronometro no aparece nunca — sin error, sin crash y
    /// sin nada que mirar. Los valores llegan boxeados en `NSNumber`, que
    /// siempre guarda los 64 bits.
    static func int64(_ any: Any?) -> Int64? {
        (any as? NSNumber)?.int64Value
    }
}
