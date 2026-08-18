//
//  ContentView.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import SwiftUI

/// Pantalla raíz: estado del emparejamiento, y una vez emparejado, la app.
struct ContentView: View {
    @EnvironmentObject private var coordinator: CredentialCoordinator
    @EnvironmentObject private var workoutCoordinator: WorkoutCoordinator
    @EnvironmentObject private var launchIntent: WatchLaunchIntent

    var body: some View {
        switch coordinator.state {
        case .waitingForPairing:
            StatusMessage(
                icon: "iphone.radiowaves.left.and.right",
                text: "Abrí TREINO en el teléfono para vincular el reloj"
            )

        case .exchanging:
            VStack(spacing: 8) {
                ProgressView()
                Text("Vinculando…").font(.footnote)
            }
            .padding()

        case .ready:
            if workoutCoordinator.session != nil {
                // Hay un entreno en curso: gana sobre todo lo demás. Sin
                // páginas laterales, para no ofrecerle al atleta arrancar otra
                // rutina mientras está a mitad de esta.
                WorkoutView()
            } else if launchIntent.pendingWorkout != nil {
                // Nos lanzó el teléfono y la adopción todavía no terminó.
                //
                // Sin esta rama caeríamos en `WatchHome`, que dibuja HOY con el
                // botón "Empezar" ACTIVO durante los cinco viajes de red que
                // tarda la adopción. El atleta ve el reloj abrirse solo, toca lo
                // único accionable que hay en pantalla, y crea una SEGUNDA
                // sesión para el mismo entreno. Ver `WatchLaunchDelegate.swift`.
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Preparando tu entreno…").font(.footnote)
                }
                .padding()
            } else {
                WatchHome()
            }

        case .failed:
            StatusMessage(
                icon: "exclamationmark.triangle",
                text: "No se pudo vincular. Abrí TREINO en el teléfono.",
                tint: .orange
            )
        }
    }
}

/// Las tres páginas de la app, con HOY en el medio.
///
/// El atleta abre el reloj en el gimnasio y lo que necesita es empezar: por eso
/// HOY es la página inicial y las otras dos se buscan a propósito, deslizando.
/// Poner planes o plantillas al arranque le cobraría un gesto al caso común.
struct WatchHome: View {

    private enum Page: Hashable { case plans, today, templates }

    @State private var page: Page = .today

    /// Sube en cada cambio de página. Las listas laterales lo usan como `id` de
    /// su tarea de carga, así que cambiarlo las relee.
    ///
    /// Vive acá y no dentro de cada lista a propósito: cuando cada una llevaba
    /// su propio contador atado a `onAppear`, la vista se pisaba sola —
    /// cancelaba su primera carga con la segunda y ninguna terminaba.
    @State private var refreshToken = 0

    @EnvironmentObject private var coordinator: CredentialCoordinator

    var body: some View {
        TabView(selection: $page) {
            RoutineListView(kind: .plans, refreshToken: refreshToken)
                .tag(Page.plans)
            TodayPage()
                .tag(Page.today)
            RoutineListView(kind: .templates, refreshToken: refreshToken)
                .tag(Page.templates)
        }
        .tabViewStyle(.page)
        // Cambiar de pagina RELEE. El reloj habla Firestore por REST y no
        // tiene listeners —es el costo de que Firestore no exista en
        // watchOS—, asi que nadie le avisa que el atleta cambio su rutina
        // activa desde el telefono. Sin esto habia que reiniciar la app para
        // ver el cambio.
        //
        // Se engancha al cambio de pagina y no a un temporizador: el atleta
        // desliza cuando quiere mirar algo, que es exactamente cuando el dato
        // tiene que estar fresco. Pollear cada N segundos gastaria bateria y
        // radio para refrescar una pantalla que nadie esta mirando.
        .onChange(of: page) { _, current in
            // Las listas laterales releen solas al cambiar el token.
            refreshToken += 1
            guard current == .today else { return }
            Task { await coordinator.loadTodaysWorkout() }
        }
        // El teléfono avisó que cambió algo. HOY ya lo relee el coordinator;
        // acá se empujan las listas laterales.
        .onChange(of: coordinator.externalRefresh) { _, _ in
            refreshToken += 1
        }
    }
}

/// La página del medio: el entreno de hoy y, más abajo, sus ejercicios.
///
/// Los ejercicios van en el MISMO scroll y no en otra página: son el detalle de
/// lo que dice arriba, no otro tema. Deslizar hacia abajo los muestra.
struct TodayPage: View {

    @EnvironmentObject private var coordinator: CredentialCoordinator

    var body: some View {
        ScrollView {
            if let workout = coordinator.todaysWorkout {
                TodaysWorkoutView(workout: workout)
            } else if coordinator.workoutError != nil {
                // El ícono de recargar ERA decorativo: un `Image` sin `Button`
                // ni gesto. Prometía una salida que no existía, y la única
                // recarga real era salir de la página y volver. Ahora acciona.
                StatusMessage(
                    icon: "arrow.clockwise",
                    text: "No se pudo cargar tu rutina",
                    tint: .orange,
                    actionTitle: "Reintentar"
                ) {
                    Task { await coordinator.loadTodaysWorkout() }
                }
            } else if coordinator.workoutLoaded {
                // Cargó bien y no hay nada que mostrar. Antes este caso caía en
                // el spinner de abajo —`todaysWorkout` y `workoutError` los dos
                // en nil— y giraba para siempre: un atleta sin rutina asignada
                // no tenía forma de saber que la carga ya había terminado.
                StatusMessage(
                    icon: "calendar",
                    text: "No tenés una rutina activa.\nActivá una desde el teléfono.",
                    tint: .secondary
                )
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Cargando tu rutina…").font(.footnote)
                }
                .padding()
            }
        }
    }
}

/// El entreno de hoy, en una pantalla de 40mm.
///
/// Austera a propósito: el nombre del día es lo que el atleta necesita leer de
/// un vistazo entre series. El resto es contexto secundario.
struct TodaysWorkoutView: View {
    @EnvironmentObject private var workoutCoordinator: WorkoutCoordinator
    let workout: TodaysWorkout

    var body: some View {
        VStack(spacing: 4) {
            Text("HOY")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(workout.dayName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text(workout.routineName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Label("\(workout.exerciseCount)", systemImage: "dumbbell")
                // La semana solo se muestra en planes periodizados: en uno de
                // una sola semana el dato es ruido.
                if workout.numWeeks > 1 {
                    Text("Sem \(workout.weekNumber + 1)/\(workout.numWeeks)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            // Sin ejercicios no hay nada que empezar: puede pasar si el plan
            // no tiene ninguno activo en esta semana.
            if workout.exercises.isEmpty {
                Text("Sin ejercicios esta semana")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                Button("Empezar") { workoutCoordinator.start(workout: workout) }
                    .font(.caption)
                    .tint(.green)
                    .padding(.top, 6)

                DayExerciseList(exercises: workout.exercises)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Los ejercicios del día, en orden, con sus series.
///
/// Es solo lectura: marcar se hace durante el entreno, no acá. Sirve para que
/// el atleta sepa qué le espera antes de darle a empezar.
struct DayExerciseList: View {

    let exercises: [WatchExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EJERCICIOS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 12, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.exerciseName)
                            .font(.system(size: 12))
                            .lineLimit(2)
                        Text(exercise.sets.count == 1 ? "1 serie" : "\(exercise.sets.count) series")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ícono + texto centrados, para los estados que no son la app en sí.
struct StatusMessage: View {

    let icon: String
    let text: String
    var tint: Color = .primary

    /// Título del botón. Nil deja el mensaje sin acción, que es lo correcto
    /// cuando no hay nada que reintentar.
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(tint)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(tint)
                    .padding(.top, 4)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(CredentialCoordinator())
        .environmentObject(WorkoutCoordinator())
}
