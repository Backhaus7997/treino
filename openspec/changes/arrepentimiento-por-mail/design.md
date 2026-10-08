# Diseño técnico: arrepentimiento-por-mail

> Botón de Arrepentimiento **verificado por mail**, con el plazo decidido por
> nuestro registro con Mercado Pago. Este documento cubre el backend (este
> repo). La parte de la landing vive en `treino-app` y va en un PR aparte (§7).
>
> ⚠️ Nada de acá se despliega sin OK de un humano. `treino-dev` es producción
> (ver `openspec/AGENTS.md`).

---

## 1. Objetivo

Hoy el Botón de Arrepentimiento (`gettreino.com/es/arrepentimiento`) manda el
pedido a una planilla y una persona lo procesa. Tiene dos huecos:

1. **No verifica la cuenta.** Cualquiera escribe cualquier mail y el pedido entra.
2. **La fecha la escribe la persona.** El formulario deja declarar una fecha de
   compra cualquiera, y `daysSincePurchaseDeclared` se calcula contra ella. Un
   pedido de hace tres meses entra como «de ayer», y uno fuera de plazo tampoco
   se rechaza: llega igual.

Esto los cierra sin automatizar lo único que no se puede deshacer, **la
devolución de la plata, que queda manual**.

## 2. NO es la baja

| | Baja de servicio | Arrepentimiento |
|---|---|---|
| Cuándo | En cualquier momento | Sólo dentro de los 10 días corridos |
| Plata | **No** se devuelve | Se devuelve **todo** lo pagado |
| Acceso | Hasta el fin del período pagado | **Se corta en el acto** (§6.5) |
| Módulo | `baja-por-mail.ts` | `arrepentimiento-por-mail.ts` |
| Términos | §7 | §6 |

Comparten el canje del link (`token-un-solo-uso.ts`) pero usan **colecciones
propias** (`mp_bajas_por_mail`, `mp_arrepentimientos_por_mail`): un token emitido
para uno no se puede canjear en el otro **por construcción**, sin depender de un
campo que alguien podría olvidarse de chequear.

## 3. Base legal

- **Ley 24.240 art. 34 / CCyC art. 1110:** 10 días corridos desde la
  contratación. Irrenunciable.
- **Términos de suscripción §6:** *«si el último día del plazo cae en un día
  inhábil, el plazo se extiende hasta el primer día hábil siguiente»*.
- **Disp. 954/2025:** el botón es público y no se puede exigir registración
  previa. **Disp. 3/2026:** habilita verificar identidad con pasos razonables,
  por medios habituales, para ese único fin: el link al mail de la cuenta.

## 4. Flujo

```
landing /arrepentimiento (form)
   │  POST → webhook (planilla + constancia con código ARR-…)   ← sigue igual
   └─ server → solicitarArrepentimientoPorMail({email, code})
                 │  responde SIEMPRE {status:"ok"} (anti-enumeración)
                 └─ mail `withdrawal-confirm` con link  …/arrepentimiento/confirmar#t=<token>

landing /arrepentimiento/confirmar   (un CLICK, no un GET)
   └─ confirmarArrepentimientoPorMail({token})
        ├─ dentro      → corta la suscripción Y EL ACCESO · avisa al equipo · mail al usuario
        ├─ a-revisar   → NO cancela · avisa al equipo · mail «lo revisamos»
        └─ fuera       → mail «venció el plazo» + ofrece la BAJA
```

## 5. El plazo (`plazo-arrepentimiento.ts`, puro)

- **La fecha sale de Mercado Pago**: `date_created` de la suscripción (cuando el
  pagador autorizó), no `mp_plans.createdAt` —el plan se crea al abrir el
  checkout y pueden pasar días hasta que alguien paga— y **nunca** la del
  formulario. Si hay varias suscripciones (cambió de plan) cuenta la **más
  reciente**; el aviso al equipo lista todas.
- **Hora de Argentina** (UTC-3, sin horario de verano). El día de la
  contratación no cuenta; el plazo vence al terminar el décimo día.
- **Fin de semana:** si el décimo día es sábado o domingo, se corre al lunes.
- **Tres respuestas, no dos:**
  - `dentro`: se puede actuar solo.
  - `a-revisar`: hasta `DIAS_DE_DUDA` (4) días **después** del último día. **No
    se rechaza ni se aprueba solo.**
  - `fuera`: se rechaza.
- **Por qué `a-revisar`:** los feriados. Un calendario de feriados argentinos
  (con los «puente» que se deciden por decreto) es un dato que se pudre en
  silencio, y el modo de falla —rechazarle a alguien un derecho irrenunciable
  porque el último día era feriado— es el que este módulo no puede tener. Cuatro
  días cubren un fin de semana largo con feriado puente.
- **Sin fecha que se entienda → `a-revisar`.** Ni aprobar ni rechazar a ciegas.

## 6. Decisiones que no son obvias

### 6.1 Todos los planes de la cuenta, no `planesQueCobran`

`planesQueCobran` excluye los planes terminales. Le sirve a la **baja** (no hay
nada que cortar), pero al arrepentimiento le sirve lo contrario: quien se dio de
baja el día 1 tiene un plan terminal, y el día 5 tiene derecho a arrepentirse
—la baja no devolvió plata—. Con ese filtro no recibía ni el mail. Lo encontró
un test de reintento; el primer test de «ya se dio de baja» pasaba porque su
fake no marcaba el plan como terminal, como sí lo hace producción.

### 6.2 El aviso al equipo no puede perderse

Se escribe **directo a la cola** con `create()` y su propio manejo de error, no
por `enqueueMail`, que devuelve `null` tanto si el mail ya existía como si la
cola falló. Acá son opuestos: la suscripción ya se canceló, y si el aviso se
perdiera en silencio nadie sabría que hay una devolución pendiente.

Si el aviso falla, se **libera el link** y el reintento —que encuentra la
suscripción ya cancelada, no vuelve a llamar a MP— vuelve a intentar el aviso.
`ALREADY_EXISTS` (código 6) se trata como éxito: el reintento es idempotente.

### 6.3 Si no se encuentra suscripción, el link se libera

El índice de búsqueda de MP tarda en incluir una suscripción recién creada
(medido: ~90 s). Quemar el link sobre un «no encontré nada» que era sólo demora
dejaría sin salida a alguien con un derecho irrenunciable.

### 6.4 La devolución sigue siendo manual

Es lo único irreversible. El mail `withdrawal-team-notice` trae todo lo
necesario para hacerla sin abrir nada más: cuenta, código, fecha de contratación
según MP, días transcurridos, monto, cobros, y los ids de las suscripciones.
Automatizarla con la API de reembolsos de MP es un cambio posterior, con la
misma garantía de este: se decide con el registro de MP, no con lo que diga el
formulario.

### 6.5 Los beneficios terminan en el momento en que se confirma

Decisión de producto (Martín, 2026-09-29): dentro de plazo se devuelve **todo**,
así que no queda acceso gratis hasta fin de período (que es lo que hace una baja
común, y lo que promete §7).

Cortar el acceso **una vez** no alcanza: el reconciliador corre de nuevo con cada
evento de Mercado Pago y con el barrido de las 03:00, y cada vez volvería a
calcular «cancelado, con período hasta el día X» y a devolvérselo. Por eso el
corte es un **marcador** en el plan (`mp_plans/{planId}.arrepentidoAtMs`) que
los dos escritores del reconciliador respetan:

- **Alumno:** `athleteSubscription.status` pasa a `expired`.
- **PF:** `currentPeriodEnd` pasa a ser el momento de la confirmación, así que
  `effectiveWeightLimit` da el límite gratis. Como cualquier baja de plan, eso
  bloquea alumnos por encima del cupo y le manda al PF el mail de degradación.
- Sólo con `status === "cancelled"`: un marcador con la suscripción todavía viva
  es una cancelación que falló, y cortarle el acceso a quien está pagando sería
  peor que no cortarlo.
- **No pisa un marcador existente**: el momento es el de la PRIMERA confirmación,
  no el del último reintento.

**Orden:** primero el aviso al equipo (la obligación de devolver), después el
corte. Si el corte falla —MP no contesta al reconciliar— el marcador ya quedó
escrito y lo aplica el próximo evento o el barrido; el link se libera para que el
reintento lo termine.

**El estado se lee POR ID, no por búsqueda** (corregido el 2026-09-29, después de
verlo fallar en producción). `/preapproval/search` —lo que usa el
reconciliador— devuelve el estado VIEJO justo después de cancelar: medido en el
sandbox, a los 0 s decía `authorized` y la lectura por id `cancelled`; a los 5 s
coincidían. Como el marcador sólo vale con `status === "cancelled"`, el
reconciliador veía una suscripción viva y lo ignoraba: el trámite corría entero
—link usado, mails enviados, marcador escrito— y el alumno seguía `active`. La
primera versión pasaba todos sus tests porque el MP falso cambiaba de estado al
instante. Ahora el corte lee cada suscripción por id (consistente) y se la pasa
al reconciliador como `conocida`, igual que el webhook (§ `conLaConocidaPrimero`).
El test usa un MP que reproduce la demora.

**Caso conocido — el resto prepago de un plan anterior NO se corta.** Un PF que
bajó de plan3 a plan1 conserva un «piso» con el resto ya pagado del plan3. Es
plata que este arrepentimiento (del plan más reciente) no devuelve, y quitársela
sería revocar algo que sí pagó: lo prohíbe la política de `subscription-state.ts`.
Si el equipo devuelve también ese pago, tiene que quitarlo a mano; el aviso lo
advierte con el plan y la fecha cuando existe.

## 7. Landing (`treino-app`, PR aparte)

- `POST /api/arrepentimiento`: además de mandar al webhook (constancia con
  código, **sin cambios**), llama a `solicitarArrepentimientoPorMail` desde el
  servidor con `{email, code}`.
- Página `/[locale]/arrepentimiento/confirmar`: lee `#t=` del fragmento, muestra
  un botón, y recién el click llama a `confirmarArrepentimientoPorMail`. Seis
  respuestas: `recibido`, `en-revision`, `fuera-de-plazo` (con la fecha en que
  venció y el link a la baja), `sin-suscripcion`, `no-disponible` y los estados
  del link (`invalido` / `ya-usado` / `vencido`).

## 8. Despliegue

Orden: `firestore:rules` (`mp_arrepentimientos_por_mail`), luego las functions:
`solicitarArrepentimientoPorMail`, `confirmarArrepentimientoPorMail` y
**`sendQueuedMail`** — sin esta última los cuatro `MailKind` nuevos tiran
`unhandled kind` y los mails no salen. Y recién después, el PR de la landing.

## 9. Preguntas abiertas

1. ~~¿Qué pasa con el acceso al arrepentirse?~~ **Resuelta el 2026-09-29:** los
   beneficios terminan en el momento en que se confirma (§6.5).
2. **El buzón del equipo** es `treino@gettreino.com` (`EQUIPO_MAILBOX`), el mismo
   que usa moderación. Si la constancia legal tiene que ir a otra casilla, se
   cambia en una constante.
3. **Los términos §6** no dicen que el acceso termina al confirmar un
   arrepentimiento; conviene una frase, y hoy no la hay. Además dicen «ningún
   trámite previo». La verificación por mail
   ocurre **después** de apretar el botón, que es lo que habilita la Disp.
   3/2026, pero conviene que el equipo legal lea si quiere una frase que lo diga.
