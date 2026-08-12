//
//  WorkoutView.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F3.
//

import SwiftUI

/// La pantalla de entrenamiento, en 40mm.
///
/// Prioridad de diseño: lo que el atleta necesita leer **entre series, con las
/// manos ocupadas**. Eso es el ejercicio actual y qué serie va. Todo lo demás
/// es secundario y va más chico.
struct WorkoutView: View {
    @EnvironmentObject private var workout: WorkoutCoordinator

    /// La sesion de entrenamiento, solo para leerle el ritmo cardiaco (F2).
    ///
    /// Es opcional a proposito: si nadie la inyecta —o si el atleta nego el
    /// permiso— la pantalla se dibuja igual, sin pulsaciones y sin hueco.
    @EnvironmentObject private var workoutSession: WorkoutSessionController

    var body: some View {
        if let exercise = workout.currentExercise, let session = workout.session {
            ScrollView {
                VStack(spacing: 6) {
                    header(exercise: exercise, session: session)

                    effortRow()

                    if let remaining = workout.restRemaining {
                        restBanner(remaining)
                    }

                    setsList(exercise: exercise, session: session)

                    if !session.pendingSets.isEmpty {
                        Label("\(session.pendingSets.count) sin subir",
                              systemImage: "arrow.up.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }

                    // Terminar aparece SOLO con todas las series de todos los
                    // ejercicios cargadas. Pedido del dueño: tenerlo siempre a
                    // la vista invita a cerrar el entreno de más, sobre todo
                    // con la muñeca mojada y el boton a un toque del ultimo
                    // circulo que se marco.
                    if workout.isFullyCompleted(session) {
                        Button("Terminar", role: .destructive) {
                            Task { await workout.finish() }
                        }
                        .font(.caption2)
                        .padding(.top, 4)
                    } else {
                        Text("Marcá todas las series para terminar")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 2)
            }
        } else {
            ProgressView()
        }
    }

    private func header(exercise: WatchExercise, session: WorkoutSession) -> some View {
        VStack(spacing: 2) {
            Text(exercise.exerciseName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text("\(workout.currentExerciseIndex + 1) de \(workout.exercises.count) · \(session.dayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Ritmo cardiaco y calorias, en una sola fila.
    ///
    /// Van juntos porque son lo mismo para el atleta —cuanto se esta
    /// esforzando— y en 42mm cada fila que se suma empuja las series fuera de
    /// pantalla, que es lo que de verdad necesita leer entre series.
    ///
    /// Si NINGUNO de los dos tiene dato no se dibuja fila, ni vacia: el hueco
    /// tambien ocupa.
    @ViewBuilder
    private func effortRow() -> some View {
        let bpm = HeartRateRules.display(reading: workoutSession.heartRate, now: Date())
        let kcal = ActiveEnergyRules.display(reading: workoutSession.activeEnergy, now: Date())

        if case .sinDatos = bpm, case .sinDatos = kcal {
            // Ninguno de los dos tiene dato: no se dibuja fila, ni vacia.
            EmptyView()
        } else {
            HStack(spacing: 10) {
                heartRateRow()
                if case .kcal(let valor) = kcal {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(valor)")
                            .monospacedDigit()
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
        }
    }

    /// El ritmo cardiaco, cuando lo hay (F2).
    ///
    /// Cuando NO lo hay no se dibuja nada: ni un guion, ni un cero, ni un aviso.
    ///
    /// No es minimalismo — es lo unico honesto que se puede hacer. En F0 se
    /// midio que una lectura negada por el atleta es INDISTINGUIBLE de "todavia
    /// no hay datos": las dos dan una query exitosa con cero muestras. La app no
    /// puede saber cual de las dos es, asi que no puede decir ninguna. Poner
    /// "sin permiso" seria adivinar, y poner "--" seria sugerir que algo se
    /// rompio cuando lo mas probable es que el sensor todavia no engancho.
    @ViewBuilder
    private func heartRateRow() -> some View {
        switch HeartRateRules.display(reading: workoutSession.heartRate, now: Date()) {
        case .sinDatos:
            EmptyView()
        case .bpm(let bpm):
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("\(bpm)")
                    .monospacedDigit()
                Text("lpm")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func restBanner(_ remaining: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
            Text("\(remaining)s")
                .monospacedDigit()
            Spacer()
            Button("Saltar") { workout.skipRest() }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.green)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15), in: Capsule())
    }

    private func setsList(exercise: WatchExercise, session: WorkoutSession) -> some View {
        // La ÚNICA serie que se puede marcar es la primera sin marcar.
        //
        // Sin esto se podía tocar la 3 sin haber hecho la 2, y quedaba un
        // hueco: el historial mostraba series salteadas, el conteo de completado
        // mentía, y en el teléfono —que sí ordena— el ejercicio se veía
        // inconsistente. En la muñeca es fácil de hacer sin querer, porque los
        // círculos están a milímetros.
        // Las filas NO salen solo del plan.
        //
        // El teléfono puede agregar series más allá de lo planificado ("agregar
        // serie"), y el reloj no tiene ese gesto. Dibujando solo `exercise.sets`,
        // esa serie quedaba en el historial y era INVISIBLE en la muñeca: el
        // atleta la cargaba en el celular y el reloj seguía mostrando el plan
        // viejo. Se dibuja hasta la serie más alta que exista, venga del plan o
        // del historial.
        let ultimaCargada = session.loggedSets
            .filter { $0.exerciseId == exercise.exerciseId }
            .map(\.setNumber)
            .max() ?? 0
        let filas = max(exercise.sets.count, ultimaCargada, 1)

        let nextSet = (1...filas).first {
            !session.isLogged(exerciseId: exercise.exerciseId, setNumber: $0)
        }
        // El setNumber es 1-based para que coincida con la identidad lógica que
        // usa el teléfono.
        return ForEach(1...filas, id: \.self) { setNumber in
            // Una fila más allá del plan no tiene prescripción: existe solo
            // porque el atleta la cargó desde el teléfono. Se muestra con lo que
            // hizo, no con un objetivo inventado.
            let spec: SetSpec? = setNumber <= exercise.sets.count
                ? exercise.sets[setNumber - 1]
                : nil
            let done = session.isLogged(
                exerciseId: exercise.exerciseId, setNumber: setNumber
            )
            // Ni las hechas, ni las que están más adelante que la próxima, ni
            // una fila sin prescripción: el reloj no ofrece cargar una serie de
            // la que no sabe el objetivo. Agregar series es del teléfono.
            let tappable = !done && setNumber == nextSet && spec != nil
            Button {
                guard let spec else { return }
                workout.logSet(
                    exerciseId: exercise.exerciseId,
                    setNumber: setNumber,
                    spec: spec,
                    restSeconds: exercise.restSeconds
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? .green : .secondary)
                    Text("\(setNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.describe(
                        spec,
                        hecha: session.loggedSets.first {
                            $0.exerciseId == exercise.exerciseId
                                && $0.setNumber == setNumber
                        }
                    ))
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            // Una serie ya cargada no se re-toca: cargarla de nuevo es un
            // no-op idempotente, pero dejarla apagada lo hace evidente. Y una
            // que todavía no toca queda apagada para no dejar huecos.
            .disabled(!tappable)
            .opacity(tappable ? 1 : 0.5)
        }
    }

    /// Qué mostrar en una fila: el objetivo del plan, o —si la fila no está en
    /// el plan— lo que el atleta efectivamente hizo.
    ///
    /// Una fila sin `spec` solo puede venir de una serie que el TELÉFONO agregó
    /// más allá del plan. No hay objetivo que mostrar y no se inventa uno: se
    /// muestra lo cargado.
    static func describe(_ spec: SetSpec?, hecha: LoggedSet?) -> String {
        guard let spec else {
            guard let hecha else { return "—" }
            let reps = hecha.reps.map(String.init) ?? "—"
            guard let peso = hecha.weightKg, peso > 0 else { return reps }
            let redondo = peso.rounded()
            let texto = peso == redondo
                ? String(Int(redondo))
                : String(format: "%.1f", peso)
            return "\(reps) × \(texto) kg"
        }
        return describe(spec)
    }

    /// El objetivo de una serie, en el mínimo de caracteres legible de reojo.
    static func describe(_ spec: SetSpec) -> String {
        var target = ""
        if let duration = spec.durationSeconds {
            target = "\(duration)s"
        } else if let reps = spec.reps {
            target = "\(reps)"
        } else if let min = spec.repsMin, let max = spec.repsMax {
            target = min == max ? "\(min)" : "\(min)–\(max)"
        }
        if let weight = spec.weightKg, weight > 0 {
            // Sin decimales cuando es redondo: "100 kg" y no "100.0 kg".
            let rounded = weight.rounded()
            let weightText = weight == rounded
                ? String(Int(rounded))
                : String(format: "%.1f", weight)
            return target.isEmpty ? "\(weightText) kg" : "\(target) × \(weightText) kg"
        }
        return target.isEmpty ? "—" : target
    }
}
