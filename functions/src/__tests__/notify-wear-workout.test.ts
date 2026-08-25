import {
  esArranqueDeEntreno,
  TYPE_WORKOUT_STARTED,
  WEAR_TOKENS_FIELD,
} from "../notifications/notify-wear-workout";

describe("esArranqueDeEntreno", () => {
  it("una sesión nueva y activa ES un arranque", () => {
    expect(esArranqueDeEntreno(false, true, "active")).toBe(true);
  });

  it("una ACTUALIZACIÓN no despierta al reloj", () => {
    // Éste es el caso caro. Hay una escritura en la sesión por cada serie
    // marcada: sin este guard, un entreno de 16 ejercicios despertaría el reloj
    // decenas de veces, y con el fullScreenIntent eso significa robarle la
    // pantalla al atleta en medio de la serie.
    expect(esArranqueDeEntreno(true, true, "active")).toBe(false);
  });

  it("una sesión que nace ya terminada no despierta nada", () => {
    // Pasa al importar historial o al cerrar un entreno que nunca se abrió en
    // el reloj.
    expect(esArranqueDeEntreno(false, true, "finished")).toBe(false);
  });

  it("un borrado no despierta nada", () => {
    expect(esArranqueDeEntreno(true, false, undefined)).toBe(false);
  });

  it("sin estado no se asume que está activa", () => {
    expect(esArranqueDeEntreno(false, true, undefined)).toBe(false);
    expect(esArranqueDeEntreno(false, true, null)).toBe(false);
  });
});

describe("contrato con los clientes", () => {
  it("el campo de tokens es el que escribe el reloj", () => {
    // Si esto cambia sin cambiar `WearPushRegistration.field`, el push deja de
    // llegar y NO falla nada: los tokens simplemente no se encuentran.
    expect(WEAR_TOKENS_FIELD).toBe("wearFcmTokens");
  });

  it("el discriminador es el que filtra WearMessagingService", () => {
    expect(TYPE_WORKOUT_STARTED).toBe("workoutStarted");
  });
});
