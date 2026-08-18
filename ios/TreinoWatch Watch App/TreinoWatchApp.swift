//
//  TreinoWatchApp.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Combine
import SwiftUI

@main
struct TreinoWatch_Watch_AppApp: App {
    /// Recibe el lanzamiento que dispara el telefono con `startWatchApp(with:)`.
    /// Ver `WatchLaunchDelegate.swift` para por que hace falta.
    @WKApplicationDelegateAdaptor(WatchLaunchDelegate.self)
    private var launchDelegate

    @StateObject private var launchIntent = WatchLaunchIntent.shared
    @StateObject private var coordinator = CredentialCoordinator()
    @StateObject private var workoutCoordinator = WorkoutCoordinator()

    /// La sesion de entrenamiento de watchOS. Vive acá y no adentro del
    /// coordinator para que ese siga sin importar HealthKit — `HKWorkoutSession`
    /// es watchOS-only y lo dejaria sin poder compilarse en el host, que es la
    /// unica forma barata de testearlo.
    @StateObject private var workoutSession = WorkoutSessionController()

    /// Le manda al telefono lo que el reloj mide, para que el dato tambien este
    /// ahi si el atleta agarra el celular (F4). Es un agregado: si falla, el
    /// reloj sigue mostrando todo igual.
    @State private var effortRelay = EffortRelay()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(workoutCoordinator)
                .environmentObject(workoutSession)
                .environmentObject(launchIntent)
                // Activa WatchConnectivity y recupera la credencial guardada.
                // Va acá y no en el init del coordinator para que el trabajo
                // arranque con la escena viva, no durante la construcción.
                .task {
                    // La sesion de entrenamiento se inyecta ANTES de restore():
                    // ese camino ya entra en modo entreno, y si llegara sin la
                    // dependencia puesta, un entreno recuperado se quedaria sin
                    // segundo plano justo despues de reabrir la app.
                    workoutCoordinator.workoutSession = workoutSession

                    // El coordinator del entreno pide su cliente al de
                    // credenciales, en vez de que uno conozca al otro.
                    workoutCoordinator.makeClient = {
                        try await coordinator.firestoreClient()
                    }
                    workoutCoordinator.makeWorkout = { routineId, day, week in
                        let (client, uid) = try await coordinator.firestoreClient()
                        // Posición EXPLÍCITA: la sesión ya existe y su día lo
                        // manda el historial. Recalcularlo hacía que el reloj
                        // mostrara los ejercicios de otro día.
                        return try await TodaysWorkoutResolver.resolve(
                            client: client,
                            uid: uid,
                            routineId: routineId,
                            dayNumber: day,
                            weekNumber: week
                        )
                    }
                    // Si nos lanzo el telefono, la sesion de HealthKit se
                    // abre YA, antes de cualquier viaje de red. Es la razon por
                    // la que watchOS nos desperto, y `begin()` es sincrono e
                    // idempotente: la llamada posterior de
                    // `WorkoutCoordinator.adoptRemoteSessionIfAny` es no-op.
                    if launchIntent.pendingWorkout != nil {
                        workoutSession.begin()
                    }

                    coordinator.start()
                    // Recupera un entreno a medias. Ya no espera a que se
                    // resuelva la rutina ACTIVA: la sesión guardada sabe de qué
                    // rutina es y se re-resuelve sola, así que un entreno
                    // arrancado desde una plantilla también sobrevive.
                    await workoutCoordinator.restore()

                    // La adopcion TERMINO, con o sin sesion encontrada. Se
                    // limpia la intencion para que "Preparando tu entreno..." no
                    // quede colgado si no habia nada que adoptar.
                    launchIntent.clear()
                }
                // Relee la rutina al volver a primer plano. Sin esto el reloj
                // solo la leia al arrancar la app: si el atleta cambiaba su
                // rutina activa desde el telefono, el reloj seguia mostrando la
                // anterior hasta que alguien lo relanzaba.
                //
                // No se refresca durante un entreno en curso: cambiar los
                // ejercicios abajo del atleta a mitad de serie seria peor que
                // mostrar un dato viejo.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        // Con un entreno abierto se reintenta la cola en vez de
                        // refrescar la rutina: cambiarle los ejercicios al
                        // atleta a mitad de serie seria peor.
                        if workoutCoordinator.session != nil {
                            // Con entreno abierto se sincroniza en AMBAS
                            // direcciones —sube lo pendiente y baja lo que se
                            // cargo desde el celular— pero NO se re-resuelve la
                            // rutina: cambiarle los ejercicios al atleta a
                            // mitad de serie seria peor que un dato viejo.
                            await workoutCoordinator.sync()
                        } else {
                            // Sin entreno local, puede haber uno abierto que
                            // arranco el telefono. Se busca ANTES de recargar
                            // la rutina: si lo hay, el reloj tiene que entrar
                            // en modo entreno, no mostrar "Empezar".
                            await workoutCoordinator.adoptRemoteSessionIfAny()
                            if workoutCoordinator.session == nil {
                                await coordinator.loadTodaysWorkout()
                            }
                        }
                    }
                }
                // El telefono aviso que algo cambio. Es el camino RAPIDO: sin
                // esto el reloj se entera recien cuando el atleta lo mira, y la
                // idea es que si empezaste a entrenar en el celular la muñeca
                // se ponga en modo entreno sola.
                // El esfuerzo se publica al telefono cuando cambia, con el
                // throttle de `EffortBroadcastRules`. Se escuchan los DOS
                // datos porque llegan por separado: el ritmo cardiaco cada
                // ~5s y las calorias cuando el builder las acumula.
                .onChange(of: workoutSession.heartRate) { _, _ in
                    publicarEsfuerzo()
                }
                .onChange(of: workoutSession.activeEnergy) { _, _ in
                    publicarEsfuerzo()
                }
                // Al cerrarse el entreno se olvida lo ultimo enviado, para que
                // el proximo no se coma el primer envio por parecerse.
                .onChange(of: workoutSession.phase) { _, phase in
                    if phase == .idle { effortRelay.reset() }
                }
                .onChange(of: coordinator.externalRefresh) { _, _ in
                    Task {
                        if workoutCoordinator.session != nil {
                            await workoutCoordinator.sync()
                        } else {
                            await workoutCoordinator.adoptRemoteSessionIfAny()
                        }
                    }
                }
        }
    }

    /// Manda el ultimo esfuerzo conocido, fechado con la medicion MAS RECIENTE
    /// de las dos.
    ///
    /// Se usa la mas reciente y no `Date()` porque la regla de antiguedad del
    /// telefono se apoya en ese timestamp: fecharlo al enviarlo lo haria pasar
    /// por mas fresco de lo que es.
    private func publicarEsfuerzo() {
        let hr = workoutSession.heartRate
        let energia = workoutSession.activeEnergy
        let fechas = [hr?.takenAt, energia?.takenAt].compactMap { $0 }
        guard let medido = fechas.max() else { return }

        effortRelay.publish(
            bpm: hr?.bpm,
            kcal: energia?.kcal,
            measuredAt: medido
        )
    }
}
