import Flutter
import HealthKit
import os

/// Abre la app del Apple Watch cuando el atleta arranca un entreno DESDE EL
/// TELEFONO, aunque el reloj tenga la app cerrada.
///
/// El mecanismo es `HKHealthStore.startWatchApp(with:)`: es la unica API de
/// Apple que despierta una app de watchOS en primer plano, y solo funciona para
/// entrenamientos. Del otro lado lo recibe `WatchLaunchDelegate.handle(_:)`.
///
/// FALLA EN SILENCIO, A PROPOSITO
/// ------------------------------
/// Decision del dueno: si el reloj esta apagado, sin bateria, no emparejado, o
/// el atleta nunca dio permiso de Salud, NO se le muestra nada. El entreno
/// arranca igual en el telefono; esto es un agregado, no un requisito. Todos los
/// caminos devuelven `false` y dejan un log, ninguno tira.
///
/// Eso NO significa tragarse el error: cada rechazo se escribe a `os_log` con su
/// motivo. La app del reloj se paso una tarde entera sin credencial porque un
/// `catch (_)` descartaba el diagnostico, y no vamos a repetirlo.
final class WatchLauncher {

    static let channelName = "com.backhaus.treino/watch_launcher"

    /// El unico metodo del canal. Lo llama el telefono al crear la sesion.
    private static let launchMethod = "launchWatchWorkout"

    private let store = HKHealthStore()
    private let log = Logger(
        subsystem: "com.backhaus.treino",
        category: "watch-launcher"
    )

    /// La configuracion tiene que ser LA MISMA que arma el reloj en
    /// `WorkoutSessionController.configuration()`: `traditionalStrengthTraining`
    /// + `indoor`. No es cosmetico — de eso dependen las calorias que estima el
    /// reloj y como aparece el entreno en la app Salud. Si una de las dos
    /// cambia, la otra tiene que cambiar igual.
    private static func configuration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        return config
    }

    @discardableResult
    static func register(with messenger: FlutterBinaryMessenger) -> WatchLauncher {
        let launcher = WatchLauncher()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [launcher] call, result in
            guard call.method == launchMethod else {
                result(FlutterMethodNotImplemented)
                return
            }
            launcher.launch { result($0) }
        }
        return launcher
    }

    private func launch(_ completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            log.notice("Sin Salud en este dispositivo: no se lanza el reloj")
            completion(false)
            return
        }

        // Se pide autorizacion para COMPARTIR entrenamientos, que es lo que
        // `startWatchApp` exige. No se pide lectura de nada: el telefono no lee
        // Salud, y agrandar el pedido agranda la superficie que Apple revisa.
        //
        // OJO: la PRIMERA vez esto abre el dialogo del sistema. Es inevitable
        // —no hay forma de lanzar el reloj sin autorizacion— y pasa una sola
        // vez. De ahi en mas es silencioso.
        let entrenamientos: Set<HKSampleType> = [HKObjectType.workoutType()]
        store.requestAuthorization(toShare: entrenamientos, read: []) { [weak self] concedido, error in
            guard let self else {
                completion(false)
                return
            }
            if let error {
                self.log.error("Salud rechazo la autorizacion: \(String(describing: error), privacy: .public)")
                completion(false)
                return
            }
            guard concedido else {
                self.log.notice("El atleta no autorizo Salud: el reloj no se lanza")
                completion(false)
                return
            }

            self.store.startWatchApp(with: Self.configuration()) { lanzado, error in
                if let error {
                    self.log.error("startWatchApp fallo: \(String(describing: error), privacy: .public)")
                }
                self.log.notice("startWatchApp devolvio \(lanzado)")
                completion(lanzado)
            }
        }
    }
}
