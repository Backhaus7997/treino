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

    var body: some View {
        if let exercise = workout.currentExercise, let session = workout.session {
            ScrollView {
                VStack(spacing: 6) {
                    header(exercise: exercise, session: session)

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
        // `enumerated` da el índice 0-based; el setNumber es 1-based para que
        // coincida con la identidad lógica que usa el teléfono.
        ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, spec in
            let setNumber = index + 1
            let done = session.isLogged(
                exerciseId: exercise.exerciseId, setNumber: setNumber
            )
            Button {
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
                    Text(Self.describe(spec))
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            // Una serie ya cargada no se re-toca: cargarla de nuevo es un
            // no-op idempotente, pero dejarla apagada lo hace evidente.
            .disabled(done)
            .opacity(done ? 0.5 : 1)
        }
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
