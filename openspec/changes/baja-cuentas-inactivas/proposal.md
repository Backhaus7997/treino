# Spec: baja automática de cuentas inactivas

**Estado:** aprobado el 2026-09-14, sin una línea escrita todavía. Arranca
cuando esté mergeado el PR #1115 (ver §10).
**Origen:** decisión del titular del 2026-09-14, sección 6 de
`docs/legal/retencion-y-borrado.md`.
**Fecha:** 2026-09-14

---

## 1. Qué se decidió

Aviso por correo a los **24 meses** de inactividad. Baja de la cuenta a los
**36 meses**, con el mismo alcance de borrado que una eliminación pedida por el
propio usuario.

El texto legal ya quedó escrito con ese plazo. Lo que no existe es el proceso
que lo ejecute.

## 2. Por qué esto bloquea la publicación

El marcador de esa sección sigue puesto a propósito. Mientras el proceso no
corra, el documento promete una baja automática que no ocurre, y el generador
aborta antes de que ese texto llegue a un usuario.

Es la misma situación que la promesa de revisar reportes en 24 horas: no es una
feature que falta, es una afirmación que sería falsa el día que se publique.
Cuando el barrido esté corriendo, se saca el marcador y ese documento queda
liberado.

---

## 3. El problema de fondo: hoy no se puede saber si una cuenta está inactiva

Esto es lo primero que hay que resolver, y no es obvio.

**No existe ninguna marca de última actividad.** `UserProfile` tiene `createdAt`
y `updatedAt`, y `updatedAt` se mueve cuando se edita el perfil, no cuando la
persona usa la app. Alguien que entrena cinco veces por semana y nunca toca su
perfil se ve idéntico a alguien que no abre la app hace dos años.

Tres opciones, en orden de lo que recomiendo:

### Opción A — `lastRefreshTime` de Firebase Auth (recomendada)

El Admin SDK expone, en los metadatos de cada usuario, cuándo fue la última vez
que su token se refrescó. El token se refresca solo cada vez que la app corre
con la sesión abierta, así que es una señal de uso real.

- No toca el cliente, no agrega escrituras, no toca las reglas.
- **Ya tiene historia**: sirve desde el día uno, sin esperar a acumular datos.
- El barrido pagina los usuarios con `listUsers` (1000 por página).
- Cuando `lastRefreshTime` viene vacío, cae a `lastSignInTime`, y si tampoco
  está, a `creationTime`.

### Opción B — un campo `lastActiveAt` en `users/{uid}`

El cliente lo escribe al abrir la app.

- Cuesta una escritura por sesión y hay que abrirle la puerta en las reglas,
  que hoy tienen allowlist de campos.
- **El reloj arranca recién el día que se despliega.** Los primeros avisos
  legítimos saldrían recién dentro de dos años.

### Opción C — derivarlo del contenido

Mirar la sesión de entrenamiento más reciente, el último mensaje, etc.

- Caro (consultas de grupo de colecciones sobre toda la base) y encima
  incompleto: alguien que sólo mira rutinas no deja rastro.

**Decisión que necesito de vos:** confirmar la opción A. Si preferís la B, el
plazo real de la primera baja se corre dos años y conviene que eso quede
escrito en el documento legal.

### Y una consecuencia de la A que hay que mirar de frente

Como la señal ya tiene historia, **es probable que en la primera corrida haya
cuentas que ya superen los 24 meses**, y el barrido les mandaría el aviso a
todas juntas. Por eso el punto 4.6, el modo de prueba, no es opcional.

---

## 4. Qué se construye

### 4.1 El barrido programado

Archivo nuevo: `functions/src/retention/sweep-inactive-accounts.ts`

Sigue el molde de `sweepAthletePaywall`, que ya existe y funciona:

```ts
export const sweepInactiveAccounts = onSchedule(
  {
    schedule: "0 5 * * *",              // 05:00 ART, después de los otros dos barridos
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => { ... },
);
```

Se registra en `functions/src/index.ts`, misma región que el resto.

La lógica de negocio va en un handler exportado aparte
(`sweepInactiveAccountsHandler(app, opts)`), como hace
`athlete-paywall-enforced.ts`, para poder testearlo sin el arnés de
`onSchedule`.

### 4.2 El aviso a los 24 meses

Sale por el outbox que ya existe: un documento en `mail_queue`, que consume
`send-queued-mail.ts` contra Resend.

- **Nuevo `MailKind`**: `"inactive-account-notice"`, agregado a la unión en
  `functions/src/mail/types.ts`, más su plantilla en la capa de templates.
- **Id del documento = clave de deduplicación**:
  `inactive-notice_{uid}_{yyyyMM}`. Si el barrido reintenta el mismo mes, el
  `create` cae sobre un documento que ya existe y no se manda dos veces.
- **Sin `prefKey`.** Es un aviso legal sobre la vida de la cuenta, no una
  notificación de producto: no debe poder apagarse desde las preferencias. Va
  en la misma categoría que el aviso de pago vencido.
- El mail dice qué pasa, cuándo, y que alcanza con entrar a la app para
  cancelarlo.

### 4.3 La baja a los 36 meses

Se reutiliza lo que ya está, no se escribe una cascada nueva:

```ts
import { runDeleteAccount } from "../delete-account";
await runDeleteAccount(app, uid, "system:retention-sweep");
```

`runDeleteAccount` está exportado aparte del callable justamente para esto. El
tercer parámetro es el proveedor de login y sólo se usa para el registro de
auditoría, así que un valor propio deja la baja automática distinguible de una
pedida por el usuario cuando alguien lea ese log.

**Condición para borrar**: 36 meses de inactividad **y** que el aviso de los 24
se haya mandado y tenga al menos 90 días. Nunca borrar sin aviso previo
registrado, aunque la cuenta tenga 5 años de inactividad.

> El piso arrancó en 30 días y pasó a 90 el 2026-09-14. En régimen estable no
> se activa nunca —el hueco entre los 24 y los 36 meses ya es de doce meses—;
> sólo muerde en el backlog, que es donde el aviso sale tarde. No se subió a
> 365 porque retener un año más datos de salud de cuentas abandonadas, sólo
> para honrar la frase «doce meses de antelación», pelearía contra el art. 4
> inc. 7 de la Ley 25.326 que la propia §6 invoca. La frase legal ahora promete
> el piso y no un número fijo.

### 4.4 Dónde se guarda el estado

Hace falta recordar a quién se le avisó y cuándo.

**Colección nueva `retention_notices/{uid}`**, sólo escrita por Cloud
Functions, con `allow read, write: if false` en las reglas, igual que
`mail_queue` y las colecciones `mp_*`.

```
retention_notices/{uid}
  noticeSentAt:  Timestamp
  lastSeenAt:    Timestamp   // la señal al momento del aviso, para auditoría
  deletedAt:     Timestamp?  // se escribe si la baja se ejecutó
```

Prefiero esto antes que un campo nuevo en `users/{uid}`: no toca la allowlist
de campos de la regla de `users`, no lo ve el cliente, y no interfiere con el
borrado en cascada.

**Ojo con la deuda que ya está anotada**: la cascada borra por campo
`athleteId` y estos documentos llevan el uid en el id, así que
`retention_notices` queda huérfano igual que `blocks` y `reports`. Se resuelve
borrándolo explícitamente en el paso 9 de la cascada, y conviene hacerlo en
este mismo trabajo porque es una línea.

### 4.5 Quiénes quedan afuera del barrido

Confirmado por el titular el 2026-09-14, y ya escrito en la sección 6 de
`docs/legal/retencion-y-borrado.md`.

Las exclusiones se evalúan **antes que la inactividad** y sacan a la cuenta del
barrido **entero**: ni aviso ni baja.

- **Entrenadores.** `runDeleteAccount` tiene un guard explícito
  (`REQ-ACCDEL-CF-003`): un trainer no puede autoborrarse, tira
  `permission-denied`. Borrar un entrenador arrastra vínculos, reseñas y chats
  de sus alumnos. El barrido sólo los lista en el log para revisión manual.
- **Cuentas con suscripción vigente.** Si alguien paga, no está abandonada.
- **Cuentas con un vínculo activo con un entrenador.** Alguien que entrena con
  un PF y no abre la app no es una cuenta muerta.

**Por qué las exclusiones alcanzan también al aviso**, y no sólo a la baja: el
mail de los 24 meses dice que a los 36 se da de baja la cuenta. Mandárselo a
alguien que nunca vamos a borrar sería exactamente la misma afirmación falsa
que este spec existe para evitar, del otro lado. Una cuenta excluida no recibe
nada.

### 4.6 Modo de prueba, obligatorio

El handler toma `{ dryRun: boolean, maxPerRun: number }`.

- En `dryRun` no escribe nada: cuenta, lista y loguea a quién le tocaría aviso
  y a quién baja.
- **La primera corrida va en `dryRun` sí o sí**, y se lee el resultado antes de
  encenderlo.
- `maxPerRun` acota cuántas cuentas se procesan por corrida. La primera tanda
  real va con un tope bajo.

---

## 5. Archivos que se tocan

| Archivo | Qué |
|---|---|
| `functions/src/retention/sweep-inactive-accounts.ts` | nuevo, el barrido |
| `functions/src/index.ts` | registrar la función |
| `functions/src/mail/types.ts` | el `MailKind` nuevo |
| la capa de templates de mail | la plantilla del aviso |
| `functions/src/delete-account.ts` | borrar `retention_notices/{uid}` en la cascada |
| `firestore.rules` | `match /retention_notices/{uid}` cerrado en los cuatro verbos |
| `docs/security.md` | fila nueva en la matriz de §1.1, con sus contadores |
| `docs/legal/retencion-y-borrado.md` | sacar el marcador, al final |

## 6. Tests

- **Unitarios del handler**, con la señal de actividad inyectada: no avisa
  antes de los 24, avisa una sola vez, no borra sin aviso previo, no borra
  antes de los 36, respeta el tope por corrida, y en `dryRun` no escribe.
- **Exclusiones**: trainer, suscripción activa y vínculo activo no se borran.
- **Reglas**, en un `retention-notices-rules.test.ts` con foco negativo: ningún
  cliente lee ni escribe `retention_notices`, ni siquiera el dueño del uid.
- **Deduplicación del mail**: dos corridas el mismo mes dejan un solo documento
  en `mail_queue`.

## 7. Lo que NO entra

- Reactivación o "papelera" de 30 días. La baja usa la cascada existente y es
  definitiva.
- Avisos dentro de la app. El canal es el correo, que es el único que llega a
  alguien que justamente no abre la app.
- Cambiar la cascada de borrado. Se reutiliza tal como está.

## 8. Qué desbloquea

Un marcador de los 13 que hoy hacen abortar el generador. Los otros doce son
las once preguntas del abogado más el estado de la marca ante el INPI.

---

## 9. Decisiones tomadas

Las tres preguntas abiertas quedaron resueltas el 2026-09-14:

1. **Señal de actividad: opción A**, el metadato de Firebase Auth.
2. **Entrenadores excluidos** del barrido, con revisión manual.
3. **Suscripción vigente o vínculo activo: excluidos** también.

El texto legal ya refleja las tres (`docs/legal/retencion-y-borrado.md` §6, PR
#1115). Si alguna cambia, el documento se ajusta **antes** de tocar el código,
no después.

## 10. Precondiciones para arrancar

- [x] #1114 mergeado
- [x] #1115 mergeado, para que la rama salga de un main que ya tenga el texto
      nuevo de §6 y no haya que resolver el mismo conflicto dos veces
- Rama: `feat/baja-cuentas-inactivas`, desde main
- Anotarse en el ledger antes de empezar (`./scripts/agent-ledger.sh claim`)
