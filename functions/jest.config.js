module.exports = {
  testEnvironment: "node",
  testMatch: ["**/src/__tests__/**/*.test.ts"],
  moduleFileExtensions: ["ts", "js"],
  transform: {
    "^.+\\.ts$": ["ts-jest", { tsconfig: "tsconfig.json" }],
  },
  // Give emulator-backed tests more time
  testTimeout: 30000,
  // Antes de la primera suite: que el emulador de Firestore no haya arrancado
  // en allow-all por falta de firestore.deploy.rules (ver el header del archivo).
  globalSetup: "<rootDir>/src/__tests__/helpers/emulador-con-reglas.global-setup.ts",
};
