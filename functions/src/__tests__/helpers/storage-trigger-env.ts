/**
 * Side-effect import que deja importable un modulo con triggers de Storage.
 *
 * ─── El problema ────────────────────────────────────────────────────────────
 *
 * `onObjectFinalized` / `onObjectDeleted` resuelven el nombre del bucket AL
 * CARGAR EL MODULO, no al invocarse: `getOptsAndBucket()` corre dentro de la
 * llamada `onObjectFinalized({...}, handler)` que esta en el cuerpo del archivo.
 * Sin `FIREBASE_CONFIG` en el entorno tira
 *
 *     Missing bucket name. If you are unit testing, please provide a bucket
 *     name [...] or by setting process.env.FIREBASE_CONFIG
 *
 * y el import explota ANTES de que corra un solo test — o sea que ni siquiera
 * se pueden testear las funciones PURAS del mismo archivo.
 *
 * Los triggers de Firestore (`onDocumentWritten`) NO tienen este problema, y
 * por eso ninguna suite anterior se lo topo: `review-aggregate.test.ts` y
 * companina importan su modulo directo y funcionan.
 *
 * ─── Por que aca y no en `jest.config.js` ───────────────────────────────────
 *
 * Un `setupFiles` global pondria `FIREBASE_CONFIG` en TODAS las suites, y hay
 * mas de cuarenta que llaman `initializeApp()`. El Admin SDK LEE esa variable
 * para completar `projectId` y `storageBucket` cuando no se los pasan, asi que
 * el arreglo de un archivo podria cambiarle el proyecto por defecto a los otros
 * — y de la peor forma, en silencio y solo en algunos.
 *
 * Importar esto primero acota el efecto al proceso de la suite que lo pide.
 * Los imports de TypeScript se ejecutan EN ORDEN DE APARICION, asi que ponerlo
 * arriba del modulo bajo test es lo que hace que llegue a tiempo. Si alguien
 * reordena los imports (o corre un organize-imports que los alfabetiza), este
 * archivo queda despues y el error vuelve — de ahi el nombre, que empieza con
 * `storage-` para que quede arriba de `../storage/...` en casi cualquier orden.
 *
 * No pisa un valor existente: si `emulators:exec` ya exporto el suyo, manda ese.
 */

process.env.FIREBASE_CONFIG =
  process.env.FIREBASE_CONFIG ??
  JSON.stringify({ storageBucket: "treino-rules-test.appspot.com" });

export {};
