//
//  WatchLaunchDelegate.swift
//  TreinoWatch Watch App
//
//  Recibe el lanzamiento que dispara el TELEFONO con
//  `HKHealthStore.startWatchApp(with:)` cuando el atleta arranca un entreno
//  ahi, con la app del reloj CERRADA.
//
//  POR QUE ESTO EXISTE Y NO ALCANZA CON `restore()`
//  ------------------------------------------------
//  Al abrirse en frio, el reloj tarda CINCO viajes de red en serie antes de
//  poder mostrar la pantalla de entreno: renovar el idToken, buscar la sesion
//  activa, renovar el token OTRA vez, resolver la rutina y leer las series.
//  Durante toda esa ventana `WorkoutCoordinator.session` sigue en nil, y
//  `ContentView` dibuja HOY — con el boton "Empezar" ACTIVO.
//
//  Eso es un riesgo de correccion, no de estetica: el atleta ve su reloj
//  abrirse solo, toca "Empezar" porque es lo unico accionable en pantalla, y
//  crea una SEGUNDA sesion para el mismo entreno. Es exactamente la familia de
//  bugs de duplicados que ya costo un ciclo entero (HANDOFF §4.3).
//
//  La intencion de lanzamiento se registra ACA, en el instante en que watchOS
//  la entrega, sin esperar a nadie. Con eso la UI puede mostrar "preparando" en
//  vez de HOY, y la ventana se cierra.
//

import Combine
import HealthKit
import SwiftUI
import WatchKit

/// La intencion de lanzamiento, compartida entre el delegate y la UI.
///
/// Es un singleton y no un `@StateObject` normal porque
/// `WKApplicationDelegate.handle(_:)` puede llegar ANTES de que la escena
/// exista: no hay a quien inyectarle nada todavia. El delegate escribe aca y la
/// vista lo observa cuando arranca.
@MainActor
final class WatchLaunchIntent: ObservableObject {

    static let shared = WatchLaunchIntent()

    /// La configuracion que mando el telefono, si nos lanzo el.
    ///
    /// Nil significa "arranque normal": el atleta abrio la app a mano.
    @Published private(set) var pendingWorkout: HKWorkoutConfiguration?

    private init() {}

    func record(_ configuration: HKWorkoutConfiguration) {
        pendingWorkout = configuration
    }

    /// Se limpia cuando la adopcion TERMINO, haya encontrado sesion o no.
    ///
    /// Sin esto, un lanzamiento cuya sesion no se puede resolver —el telefono
    /// escribio la sesion pero el reloj no llega a Firestore, por ejemplo—
    /// dejaria "Preparando tu entreno..." para siempre. Es el mismo error que
    /// el spinner eterno de HOY, y no lo vamos a repetir tres pantallas mas
    /// alla.
    func clear() {
        pendingWorkout = nil
    }
}

/// El delegate de watchOS. Su unico trabajo es recibir el lanzamiento.
final class WatchLaunchDelegate: NSObject, WKApplicationDelegate {

    /// watchOS entrega aca el `HKWorkoutConfiguration` que el telefono paso a
    /// `startWatchApp(with:)`.
    ///
    /// NO abre la sesion de HealthKit aca: eso vive en `WorkoutSessionController`,
    /// que es `@MainActor` y dueno de su ciclo de vida. Duplicar el `begin()`
    /// desde dos lugares es como se termina con dos `HKWorkoutSession` abiertas.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchLaunchIntent.shared.record(workoutConfiguration)
        }
    }
}
