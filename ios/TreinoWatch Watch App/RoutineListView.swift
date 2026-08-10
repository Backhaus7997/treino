//
//  RoutineListView.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F5.
//

import Combine
import SwiftUI

/// Cuál de las dos listas laterales es.
enum RoutineListKind {
    /// Planes a nombre del atleta: los del PF y los que se armó él.
    case plans
    /// Plantillas para arrancar sin que sean un plan suyo.
    case templates

    var title: String {
        switch self {
        case .plans: return "MIS PLANES"
        case .templates: return "PLANTILLAS"
        }
    }

    var emptyMessage: String {
        switch self {
        case .plans: return "No tenés planes cargados"
        case .templates: return "No hay plantillas disponibles"
        }
    }
}

/// Carga una de las listas de rutinas.
///
/// Vive por lista y no en `CredentialCoordinator` a propósito: la credencial es
/// una cosa y el catálogo es otra, y meter todo en un mismo objeto haría que
/// cada refresco de rutinas notificara a media app.
@MainActor
final class RoutineListModel: ObservableObject {

    @Published private(set) var routines: [RoutineSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false

    /// Rutina que el atleta está mirando en el detalle, o nil.
    @Published var selected: RoutineSummary?

    /// Se recarga solo la primera vez: volver a pasar por la página no debería
    /// disparar cuatro queries cada vez que el atleta desliza.
    private var loadedOnce = false

    func loadIfNeeded(
        kind: RoutineListKind,
        makeClient: @escaping () async throws -> (FirestoreREST, String)
    ) async {
        guard !loadedOnce else { return }
        await reload(kind: kind, makeClient: makeClient)
    }

    func reload(
        kind: RoutineListKind,
        makeClient: @escaping () async throws -> (FirestoreREST, String)
    ) async {
        isLoading = true
        failed = false
        do {
            let (client, uid) = try await makeClient()
            switch kind {
            case .plans:
                routines = try await RoutineCatalog.plans(client: client, uid: uid)
            case .templates:
                routines = try await RoutineCatalog.templates(client: client)
            }
            loadedOnce = true
        } catch {
            failed = true
        }
        isLoading = false
    }
}

/// Una de las listas laterales: planes a la izquierda, plantillas a la derecha.
struct RoutineListView: View {

    let kind: RoutineListKind

    @EnvironmentObject private var coordinator: CredentialCoordinator
    @StateObject private var model = RoutineListModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if model.isLoading && model.routines.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.failed && model.routines.isEmpty {
                    Text("No se pudo cargar")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if model.routines.isEmpty {
                    Text(kind.emptyMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.routines) { routine in
                        Button { model.selected = routine } label: {
                            RoutineRow(routine: routine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .task {
            await model.loadIfNeeded(kind: kind, makeClient: makeClient)
        }
        // Hoja y no navegación: en el reloj el push se cierra con un deslizar
        // horizontal, que es el MISMO gesto que cambia de página. La hoja se
        // cierra hacia abajo y no pelea con el paginado.
        .sheet(item: $model.selected) { routine in
            RoutineDetailView(routine: routine, kind: kind)
        }
    }

    private func makeClient() async throws -> (FirestoreREST, String) {
        try await coordinator.firestoreClient()
    }
}

/// Una fila de la lista. Sin el detalle del plan: en 187 puntos de ancho, el
/// nombre y una chapita es todo lo que se lee de un vistazo.
struct RoutineRow: View {

    let routine: RoutineSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(routine.name)
                    .font(.footnote)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if let badge = routine.origin.badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        // Singular a mano: el reloj no tiene l10n propia, y "1 días" se lee
        // descuidado en una pantalla donde entran cuatro palabras.
        let days = routine.dayCount == 1 ? "1 día" : "\(routine.dayCount) días"
        guard routine.numWeeks > 1 else { return days }
        return "\(days) · \(routine.numWeeks) sem"
    }
}

/// Qué hacer con una rutina de la lista.
///
/// Las dos acciones son distintas a propósito y el dueño las pidió separadas:
/// **empezar** arranca ese entreno sin tocar nada, y **activar** cambia cuál es
/// la rutina del atleta en TODA la app —teléfono incluido—. Mezclarlas haría que
/// probar una plantilla le pisara el plan que le armó su PF.
///
/// ⚠️ **«Activar» SOLO se ofrece sobre planes, nunca sobre plantillas.**
/// `resolveActiveRoutineId` busca el marcador `activeRoutineId` dentro de las
/// listas de asignadas y auto-creadas: una plantilla no está en ninguna de las
/// dos, así que escribir su id ahí es una escritura que sale bien y NO HACE
/// NADA — el atleta ve "listo" y HOY le sigue mostrando la rutina de antes. Es
/// el mismo criterio del teléfono, donde "Marcar como activa" aparece en
/// RUTINAS y no en PLANTILLAS.
///
/// Hacer propia una plantilla (copiarla a las rutinas del atleta) se hace desde
/// el teléfono: implica escribir la rutina entera con sus días y series, y es
/// otra funcionalidad.
struct RoutineDetailView: View {

    let routine: RoutineSummary
    let kind: RoutineListKind

    @EnvironmentObject private var coordinator: CredentialCoordinator
    @EnvironmentObject private var workoutCoordinator: WorkoutCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var failed = false
    @State private var errorMessage = RoutineDetailView.genericError

    private static let genericError = "No se pudo. Probá de nuevo."

    /// Solo los planes pueden ser la rutina activa — ver la nota del tipo.
    private var canActivate: Bool { kind == .plans }

    private var hint: String {
        canActivate
            ? "«Empezar» no cambia tu rutina activa. «Activar» sí, también en el teléfono."
            : "Entrenás esta plantilla sin cambiar tu rutina activa."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(routine.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                if busy {
                    ProgressView()
                } else {
                    Button("Empezar", action: startNow)
                        .tint(.green)
                    if canActivate {
                        Button("Activar", action: activate)
                            .tint(.blue)
                    }
                }

                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if failed {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Arranca ESTA rutina sin tocar cuál es la activa del atleta.
    ///
    /// El día y la semana salen de las sesiones terminadas de esta misma rutina,
    /// así que una plantilla ya empezada retoma donde iba.
    private func startNow() {
        perform {
            let (client, uid) = try await coordinator.firestoreClient()
            let workout = try await TodaysWorkoutResolver.resolve(
                client: client, uid: uid, routineId: routine.id
            )
            guard let workout, !workout.exercises.isEmpty else {
                errorMessage = "Esta rutina no tiene ejercicios para hoy"
                return false
            }
            workoutCoordinator.start(workout: workout)
            return true
        }
    }

    /// Cambia la rutina activa del atleta, y nada más.
    ///
    /// NO arranca el entreno: activar es cambiar una preferencia, y encadenarle
    /// un entreno haría imposible cambiar de plan sin ponerte a entrenar. Al
    /// cerrar, HOY ya muestra la rutina nueva con su botón de empezar.
    private func activate() {
        perform {
            let (client, uid) = try await coordinator.firestoreClient()
            try await RoutineCatalog.setActiveRoutine(
                client: client, uid: uid, routineId: routine.id
            )
            // Relee HOY para que el cambio se vea al volver, sin esperar a que
            // el reloj pase por segundo plano.
            await coordinator.loadTodaysWorkout()
            return true
        }
    }

    /// Corre una acción mostrando el spinner y cerrando la hoja si salió bien.
    private func perform(_ action: @escaping () async throws -> Bool) {
        busy = true
        failed = false
        errorMessage = Self.genericError
        Task {
            do {
                let ok = try await action()
                busy = false
                if ok { dismiss() } else { failed = true }
            } catch {
                busy = false
                failed = true
            }
        }
    }
}
