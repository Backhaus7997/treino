module.exports = {
  root: true,
  env: {
    es2022: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.eslint.json"],
    sourceType: "module",
    tsconfigRootDir: __dirname,
  },
  plugins: [
    "@typescript-eslint",
  ],
  ignorePatterns: [
    "/lib/**/*",
    ".eslintrc.js",
    // Salida de generador, igual que `/lib`. Un `.g.ts` no se arregla a mano
    // —el proximo `python3 scripts/build_moderation_list.py` lo pisa—, asi que
    // un warning ahi no se puede accionar y solo suma ruido permanente a la
    // salida del lint. `tsc` los sigue mirando, que es lo que de verdad
    // importa: los errores de TIPO no se saltean, solo los de estilo.
    "/src/**/*.g.ts",
  ],
  rules: {
    "quotes": ["error", "double"],
    "indent": ["error", 2],
    "max-len": ["warn", { "code": 120 }],
    "@typescript-eslint/no-explicit-any": "warn",
  },
};
