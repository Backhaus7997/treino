/**
 * El nombre de la colección del registro de avisos de retención, solo.
 *
 * Vive en un módulo propio —sin imports— para romper un ciclo real: el barrido
 * (`sweep-inactive-accounts.ts`) importa `runDeleteAccount`, que importa
 * `cascade/users.ts`, que necesita este nombre para borrar el documento en el
 * paso 9. Si la constante viviera en el barrido, el ciclo existiría y en
 * CommonJS se resolvería con un `undefined` en tiempo de carga según quién
 * importe primero — o sea, una colección llamada `undefined` en producción.
 *
 * Alternativa descartada: escribir el literal en los dos lados. Dos copias de
 * un nombre de colección se separan el día que alguien lo renombra, y el
 * síntoma sería el silencioso: la cascada borrando una colección que no existe.
 */
export const RETENTION_NOTICES_COLLECTION = "retention_notices";
