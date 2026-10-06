// Flat config (ESLint 9+). Reemplaza al `.eslintrc.js` de ESLint 8 con las
// MISMAS reglas e ignores: eslint:recommended + @typescript-eslint/recommended
// (con type information vía tsconfig.eslint.json) y cuatro reglas propias.
// `eslint-config-google` figuraba en devDependencies pero nunca estuvo en
// `extends`, así que no se migra: se quitó del package.json.
const js = require("@eslint/js");
const tseslint = require("typescript-eslint");
const globals = require("globals");

module.exports = tseslint.config(
  {
    ignores: [
      "lib/**",
      "eslint.config.js",
      // Salida de generador, igual que `lib`. Un `.g.ts` no se arregla a mano
      // —el proximo `python3 scripts/build_moderation_list.py` lo pisa—, asi que
      // un warning ahi no se puede accionar y solo suma ruido permanente a la
      // salida del lint. `tsc` los sigue mirando, que es lo que de verdad
      // importa: los errores de TIPO no se saltean, solo los de estilo.
      "src/**/*.g.ts",
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.ts"],
    // ESLint 8 no reportaba directivas `eslint-disable` sin uso; 9+ sí (warning).
    // Se apaga para no sumar warnings que el lint viejo no daba.
    linterOptions: {reportUnusedDisableDirectives: "off"},
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {...globals.es2021, ...globals.node},
      parserOptions: {
        project: ["tsconfig.eslint.json"],
        tsconfigRootDir: __dirname,
      },
    },
    rules: {
      "quotes": ["error", "double"],
      "indent": ["error", 2],
      "max-len": ["warn", {"code": 120}],
      "@typescript-eslint/no-explicit-any": "warn",
    },
  },
);
