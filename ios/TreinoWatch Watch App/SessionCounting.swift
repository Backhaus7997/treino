//
//  SessionCounting.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`.
//

import Foundation

/// Si un documento de sesión cuenta como entrenamiento **HECHO**.
///
/// ⚠️ **PUERTO LITERAL de `sessionCountsAsWorkout` en
/// `lib/features/workout/domain/session.dart`.** No es "una implementación
/// equivalente": es la misma regla escrita dos veces.
///
/// Los fixtures de `conformance/session_counting.json` son el contrato entre
/// las dos, y `conformance/run_swift.sh` los corre contra ESTA función.
///
/// ── Por qué existe como función aparte ────────────────────────────────────
///
/// Esta regla vivía suelta dentro de `findLastFinishedSession`, y ahí no la
/// cubría ningún contrato. El resultado fue un bug: el reloj filtraba por
/// `finishedAt` presente mientras el teléfono usaba
/// `status == finished && wasFullyCompleted`. **No son el mismo conjunto** —
/// abandonar un entreno guarda `status=finished` con `wasFullyCompleted=false`.
/// Los dos clientes avanzaban el plan desde sesiones DISTINTAS y cada
/// dispositivo mostraba otro día.
///
/// `plan_advance.json` estuvo en verde con sus 35 casos todo ese tiempo, porque
/// cubre la DECISIÓN y no QUE SE LE PASA. Sacar la regla acá la vuelve
/// contrastable contra Dart.
///
/// ── La distinción que hay que tener presente ──────────────────────────────
///
/// **"Cerrada" no es "hecha".** Una sesión abandonada está cerrada: no se puede
/// adoptar, no se puede seguir escribiendo en ella, y el reloj debe salir del
/// modo entreno si el teléfono la cerró. Pero NO avanza el plan.
///
/// Por eso los otros usos de `finishedAt` en el reloj —`findAnyActiveSession`,
/// `isFinished`— NO usan esta función: ahí lo que importa es si está cerrada.
///
/// - Parameters:
///   - status: valor de wire del campo `status`. `nil` si está ausente o es
///     nulo explícito — el reloj no puede distinguirlos y no necesita hacerlo.
///   - wasFullyCompleted: valor de wire del campo homónimo. `nil` cuenta como
///     `false`, igual que el `@Default(false)` del lado Dart. Un documento
///     viejo sin la clave NO puede empezar a contar de golpe.
func sessionCountsAsWorkout(status: String?, wasFullyCompleted: Bool?) -> Bool {
    // Igualdad contra "finished", nunca desigualdad contra "active": si algún
    // día se agrega un estado nuevo, un reloj viejo no puede empezar a contarlo
    // solo porque no reconoce el valor.
    status == "finished" && wasFullyCompleted == true
}
