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

    /// Si esta abierto el pedido de confirmacion para abandonar.
    ///
    /// El boton no abandona: abre esto. Un solo toque no puede tirar un entreno
    /// a la basura — y menos en una pantalla del tamaño de una moneda.
    @State private var confirmandoAbandono = false

    var body: some View {
        // El cronometro de un ejercicio POR TIEMPO gana sobre todo lo demas.
        //
        // Pedido del dueno: que tome prioridad en la pantalla y que hasta que no
        // termine no se pueda marcar la serie. Con la pantalla tomada no hay
        // ninguna fila que tocar, asi que la regla se cumple por construccion en
        // vez de por un `disabled` que hay que acordarse de poner.
        if let cuenta = workout.durationSet {
            durationTimerScreen(cuenta)
        } else if let espejo = workout.phoneTimer {
            // El cronometro que arranco en el TELEFONO. Misma prioridad de
            // pantalla por el mismo motivo: mientras dura la serie no hay nada
            // que marcar.
            phoneTimerScreen(espejo)
        } else if let exercise = workout.currentExercise, let session = workout.session {
            ScrollView {
                VStack(spacing: 6) {
                    header(exercise: exercise, session: session)

                    effortRow()

                    if let remaining = workout.restRemaining {
                        restBanner(remaining)
                    }

                    setsList(exercise: exercise, session: session)

                    // El cartel "N sin subir" se saco por pedido del dueno
                    // (2026-08-19): aparecia en cada serie marcada y ensuciaba
                    // la pantalla.
                    //
                    // No deja al atleta ciego: el caso PELIGROSO —abandonar un
                    // entreno con series sin subir, que es un no-op silencioso—
                    // tiene su propio banner explicito en `WorkoutCloseFeedback`
                    // ("Falta subir N series. El entreno sigue abierto") con
                    // boton de reintentar. Ese aviso llega cuando importa, en
                    // vez de estar prendido todo el tiempo.
                    //
                    // Y la causa de fondo se ataco en el mismo commit: con el
                    // idToken cacheado las series suben en menos viajes, asi que
                    // la cola casi no existe.

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

                        // Salida para un entreno que NO se puede completar
                        // (HANDOFF §8.3). Si te lesionás a mitad y no tenés el
                        // teléfono a mano, antes no había ningún gesto: la
                        // sesión quedaba abierta para siempre.
                        //
                        // VISIBILIDAD, revisada por el dueño el 2026-08-18 con
                        // la app corriendo en la muñeca: "casi ni lo veo, lo vi
                        // de pedo". La versión original era deliberadamente poco
                        // accesible —texto plano de 10pt en gris, pegado debajo
                        // de otra línea gris— y en pantalla resultó invisible,
                        // no discreta.
                        //
                        // El criterio nuevo es que se ENCUENTRE sin que se TOQUE
                        // sin querer, y son dos cosas distintas:
                        //   - Se encuentra: forma de botón (`.bordered`), que lo
                        //     despega del texto de arriba, y tamaño legible.
                        //   - No se toca sin querer: sigue ABAJO de todo y
                        //     separado, el destructivo de verdad ("Terminar")
                        //     se gana marcando series, y sobre todo NO EJECUTA
                        //     NADA por sí solo — abre un `confirmationDialog`.
                        //     Esa confirmación es la defensa real contra el
                        //     toque accidental; la invisibilidad nunca lo fue.
                        Button("Abandonar entreno") {
                            confirmandoAbandono = true
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .padding(.top, 12)
                    }

                    // Por que NO se cerro el entreno.
                    //
                    // Va afuera del if/else porque las dos salidas —TERMINAR y
                    // ABANDONAR— llaman a `finish()` y las dos pueden fallar
                    // igual. Antes no habia nada: el fallo por pendientes
                    // cortaba en silencio y el del historial se guardaba en
                    // `syncError`, que no lo renderizaba ninguna vista.
                    if let motivo = workout.closeFailure {
                        closeFailureBanner(motivo)
                    }
                }
                .padding(.horizontal, 2)
            }
            .confirmationDialog(
                "¿Abandonar el entreno?",
                isPresented: $confirmandoAbandono,
                titleVisibility: .visible
            ) {
                Button("Abandonar", role: .destructive) {
                    Task { await workout.abandon() }
                }
                Button("Seguir entrenando", role: .cancel) {}
            } message: {
                // Mismo contrato que el telefono: lo hecho NO se pierde.
                Text("Se guarda lo que hiciste hasta acá.")
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

            // Sin esto el atleta no tiene forma de saber que esta adentro de
            // una superserie: la pantalla del reloj muestra UN ejercicio, y
            // saltar de A a B entre series parece un error de la app en vez de
            // el entrenamiento que pidio su plan.
            if let cursor = workout.currentCursor,
               let vuelta = cursor.round,
               let total = cursor.totalRounds {
                Text("SUPERSERIE · VUELTA \(vuelta)/\(total)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// La cuenta regresiva de un ejercicio por tiempo, a pantalla completa.
    ///
    /// No hay boton de "hecho": al llegar a cero la serie se marca SOLA y el
    /// reloj vibra. Un ejercicio por tiempo no se completa por decision del
    /// atleta, se completa cuando pasa el tiempo.
    private func durationTimerScreen(_ cuenta: WorkoutCoordinator.DurationSet) -> some View {
        VStack(spacing: 8) {
            Text(nombreDe(cuenta.exerciseId))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text(CountdownRules.display(remaining: workout.durationRemaining))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(.green)

            Text("serie \(cuenta.setNumber) · \(cuenta.totalSeconds)s")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // El pulso tambien acá: es el dato que el atleta mira mientras
            // aguanta, y esta pantalla le tapa la otra. Sin esto, arrancar el
            // cronometro le sacaba de la vista lo unico que estaba mirando.
            effortRow()

            // Salida sin cargar la serie. Sin esto, un toque equivocado deja al
            // atleta mirando una cuenta que no pidio y sin forma de volver.
            Button("Cancelar") { workout.cancelDurationSet() }
                .font(.caption2)
                .buttonStyle(.bordered)
                .tint(.secondary)
                .padding(.top, 6)
        }
        .padding()
    }

    /// La cuenta regresiva de una serie que arranco en el TELEFONO.
    ///
    /// Se ve igual que la propia salvo por dos cosas, y las dos importan:
    ///
    /// 1. Dice de donde viene. Sin eso el atleta no tiene como saber por que
    ///    esta cuenta no responde al reloj.
    /// 2. El boton OCULTA, no cancela. Cancelar de verdad la serie es del
    ///    telefono, que es su dueno; desde aca solo se saca de la pantalla.
    ///
    /// Existe el boton igual —aunque el espejo se apague solo al llegar a
    /// cero— porque el aviso de cancelacion viaja por `sendMessage` y ese exige
    /// alcanzabilidad: si el atleta cancela en el telefono y el bluetooth se
    /// cayo, sin salida la muneca queda tomada hasta que venza la cuenta.
    private func phoneTimerScreen(_ espejo: PhoneTimer) -> some View {
        VStack(spacing: 8) {
            Text(nombreDe(espejo.exerciseId))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            Text(CountdownRules.display(remaining: workout.phoneTimerRemaining))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(.green)

            Text("serie \(espejo.setNumber) · en el telefono")
                .font(.caption2)
                .foregroundStyle(.secondary)

            effortRow()

            Button("Ocultar") { workout.clearPhoneTimer() }
                .font(.caption2)
                .buttonStyle(.bordered)
                .tint(.secondary)
                .padding(.top, 6)
        }
        .padding()
    }

    /// El nombre del ejercicio del cronometro. Se busca por id porque el cursor
    /// puede haberse movido mientras corre la cuenta.
    private func nombreDe(_ exerciseId: String) -> String {
        workout.exercises.first { $0.exerciseId == exerciseId }?.exerciseName
            ?? "Ejercicio"
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

    /// El aviso de que el entreno NO se cerró, con la salida.
    ///
    /// Naranja y no rojo a propósito: no se perdió nada, la sesión sigue viva y
    /// lo hecho está guardado. Rojo diría "pasó algo grave", y lo que pasó es
    /// que no hay señal.
    ///
    /// REINTENTAR llama a `finish()`, el mismo camino que falló. Es lo que hace
    /// el teléfono en `_showFinishError` — un SnackBar con acción Reintentar—, y
    /// es lo único accionable: cuando vuelva la conectividad, el mismo botón
    /// cierra. Sin él, el atleta tiene el diagnóstico y ninguna salida.
    private func closeFailureBanner(_ motivo: WorkoutCloseFailure) -> some View {
        VStack(spacing: 4) {
            Text(motivo.mensaje)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(.orange)

            Button("Reintentar") {
                Task { await workout.finish() }
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 6)
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

        // La serie ofrecida sale del CURSOR y no del primer hueco local.
        //
        // En el flujo normal dan lo mismo, pero divergen cuando el estado viene
        // desordenado —el telefono cargo series salteadas, o el reloj adelanto
        // un miembro de la superserie— y ahi el hueco local ofreceria una serie
        // que la regla compartida no autoriza. El cursor es la unica autoridad.
        let cursor = workout.currentCursor
        let esElActual = cursor.map {
            $0.exerciseIndex < workout.exercises.count
                && workout.exercises[$0.exerciseIndex].exerciseId == exercise.exerciseId
        } ?? false
        let nextSet: Int? = esElActual
            ? cursor?.setNumber
            : nil
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
            // Un ejercicio POR TIEMPO no se marca: se cronometra.
            //
            // El toque arranca la cuenta en vez de cargar la serie, y la serie
            // se carga sola al llegar a cero. Marcarla a mano permitiria darla
            // por hecha sin haberla hecho, que es justo lo que el dueno pidio
            // evitar.
            let porTiempo = (spec?.durationSeconds ?? 0) > 0
            Button {
                guard let spec else { return }
                if porTiempo {
                    workout.startDurationSet(
                        exerciseId: exercise.exerciseId,
                        setNumber: setNumber,
                        spec: spec,
                        restSeconds: exercise.restSeconds
                    )
                } else {
                    workout.logSet(
                        exerciseId: exercise.exerciseId,
                        setNumber: setNumber,
                        spec: spec,
                        restSeconds: exercise.restSeconds
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: done
                            ? "checkmark.circle.fill"
                            : (porTiempo && tappable ? "timer" : "circle"))
                        .foregroundStyle(done ? .green : (porTiempo && tappable ? .green : .secondary))
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
