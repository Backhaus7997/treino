# Auditoría — documentos legales vigentes vs. lo que la app hace

Los Términos y la Política de Privacidad que hoy ve el usuario viven en
[`lib/features/auth/presentation/legal/legal_content.dart`](../../lib/features/auth/presentation/legal/legal_content.dart)
y se renderizan con `LegalDocumentScreen`. Están fechados el **12 de junio de
2026** y el propio archivo se declara borrador pendiente de revisión legal.

Este documento contrasta ese texto contra el código y las reglas de Firestore,
verificado el **2026-08-31**. Cada hallazgo cita la evidencia.

> **Cómo leer esto.** No es una lista de mejoras de redacción. Son puntos donde
> el documento publicado **describe mal** lo que el binario hace. Una política de
> privacidad inexacta no es un documento flojo: es una declaración falsa frente
> al usuario, frente a la AAIP y frente a las stores.

---

## Resumen

| Severidad | Cantidad | Qué son |
|---|---|---|
| 🔴 Crítico | 5 | El documento afirma algo que el código contradice, u omite una categoría entera de datos sensibles |
| 🟠 Alto | 7 | Omisión material: tratamiento real no declarado |
| 🟡 Medio | 6 | Cláusula inejecutable, dato de contacto inválido o falta de concreción |

---

## 🔴 Críticos

### C1 — La política no menciona datos de salud. La app recolecta siete tipos.

**Dice:** «tus datos de entrenamiento (rutinas, sesiones, pesos, progreso)»
(`kPrivacySections`, sección 1).

**Hace:**

| Dato | Dónde |
|---|---|
| 20+ medidas corporales, % de grasa, masa muscular | `measurement.dart:21-49` — `fatPercentage`, `muscleMassKg`, `waistCm`, `bicepsFlexedLCm`… |
| Dolor declarado por ejercicio, **con foto adjunta** | `exerciseFeedback` con `kind: discomfort` + `photoUrl` |
| Check-in diario: ánimo, dolor sí/no, zonas del cuerpo doloridas | `check_in.dart:131-147` — `feeling`, `hasPain`, `painAreas` |
| Planes de alimentación | `nutrition_plans`, `nutrition_plan.dart` |
| Tests de rendimiento físico | `performance_tests`, incluye `cooperMeters`, `sitAndReachCm` |
| Altura y peso corporal | `UserProfile.heightCm`, `bodyWeightKg` |
| Historial completo de sesiones y series | `users/{uid}/sessions/{id}/setLogs` |

**Por qué es crítico.** El art. 2 de la Ley 25.326 define como **dato sensible**
la información referente a la salud. El art. 7 exige para tratarlos
**consentimiento expreso**, con finalidad determinada, y prohíbe recolectarlos
sin ella. El consentimiento genérico de la sección 3 («que prestás al aceptar
esta política») no cumple ese estándar: el usuario no puede consentir
expresamente un tratamiento que el documento **no le describe**.

Google clasifica salud como categoría especial en Data Safety y ya está
declarada en [`store/privacy/data-safety.md`](../../store/privacy/data-safety.md).
O sea: **el equipo ya sabe que recolecta datos de salud, lo declaró ante Google,
y no se lo dijo al usuario.** Esa asimetría es el hallazgo.

**Acción:** sección dedicada a datos de salud + flujo de consentimiento
específico, separado del checkbox de Términos.

---

### C2 — «Tu ubicación no es visible para otros usuarios» es falso para el PF.

**Dice:** «Tu ubicación no es visible para otros usuarios» (sección 4).

**Hace:** `TrainerLocation` persiste `lat` y `lng` crudos —no sólo el geohash— y
esos campos se copian a `trainerPublicProfiles`, que es legible por cualquier
usuario autenticado y se dibuja en el mapa de descubrimiento
(`trainers_map_view.dart`). Seteados desde `profile_edit_trainer_screen.dart:1049-1050`.

El hallazgo ya estaba documentado del lado de las stores
([`data-safety.md`](../../store/privacy/data-safety.md), sección Ubicación:
«⚠️ Para el trainer hay que declarar ubicación precisa»). La política vigente
dice lo contrario.

**Por qué es crítico.** No es una omisión, es una afirmación contraria al
hecho, sobre un dato de geolocalización precisa. Es la clase de contradicción
que se prueba en cinco minutos abriendo la app.

**Acción:** distinguir explícitamente atleta (ubicación opcional, no publicada)
de PF (ubicación de trabajo **publicada a propósito** — es el modelo de negocio).

---

### C3 — El PF lleva registros privados sobre el alumno que el alumno nunca ve.

**Hace:** tres colecciones son trainer-only y el atleta no tiene acceso de
lectura por reglas:

| Colección | Contenido | Regla |
|---|---|---|
| `athlete_notes` | Nota libre del PF sobre el alumno | `firestore.rules:2645` — read sólo `resource.data.trainerId` |
| `follow_up_entries` | Log cronológico de seguimiento | `firestore.rules:2730` — «alumno NUNCA lo ve» (comentario del propio archivo) |
| `athlete_files` | Archivos que el PF sube sobre el alumno (hasta 10 MB) | `firestore.rules:2705` |

**Dice:** nada. La política no los menciona.

**Por qué es crítico.** Son datos personales **del atleta**, tratados en
infraestructura de TREINO. El art. 14 de la Ley 25.326 le da al titular derecho
de acceso a *toda* información sobre él que conste en la base. Una nota que el
PF escribe sobre un alumno entra en ese derecho, aunque la UI no la muestre.

Hoy, si un atleta ejerce habeas data, TREINO tiene que entregarle contenido que
su propio producto le oculta — y ni el atleta ni el PF fueron advertidos de eso.

**Acción:** declararlo en la política, advertírselo al PF en su contrato, y
definir el procedimiento de acceso. Es también una decisión de producto: quizá
el PF deba saber que lo que escribe es reclamable.

---

### C4 — Cláusula de edad inejecutable, y por debajo de lo prudente.

**Dice:** «Debés tener al menos 16 años» (Términos, sección 4) y «no está
dirigido a menores de 16 años» (Privacidad, sección 9).

**Hace:** no hay ningún control de edad. `UserProfile.bornAt` es **opcional**
(`user_profile.dart:49`), se carga desde el editor de perfil —no en el alta— y
ninguna regla ni validador lo compara contra una edad mínima. Un chico de 12
crea cuenta sin fricción.

**Por qué es crítico.** Es una cláusula que la propia app no hace cumplir, sobre
un servicio que recolecta datos de salud y vende suscripciones. Frente a un
reclamo, «lo decían los términos» no sirve si el sistema nunca lo verificó.

Y 16 es una elección agresiva para este producto. Con datos sensibles de salud y
un marketplace pago, 18 es la respuesta limpia; cualquier cosa por debajo exige
flujo de consentimiento parental verificable.

**Acción:** decisión de producto + gate real en el alta. Ver el PDF de tareas.

---

### C5 — El responsable del tratamiento no está identificado.

**Dice:** «El responsable del tratamiento de tus datos es TREINO» (sección 11),
con contacto `equipo@treino.app`.

**Problemas, dos:**

1. **«TREINO» no es un sujeto de derecho.** Falta razón social o nombre de la
   persona humana, CUIT y domicilio. El art. 6 inc. c) de la Ley 25.326 exige
   identificar al responsable de la base. Es el requisito más elemental y es el
   único que no se puede redactar sin vos.
2. **El dominio del email es incorrecto.** El dominio real del proyecto es
   `gettreino.com` (ver [`docs/runbook-dominio-y-email.md`](../runbook-dominio-y-email.md),
   DNS en Vercel). `treino.app` no aparece en ninguna configuración del repo. Es
   muy probable que ese buzón **no exista**, o sea: un canal de ejercicio de
   derechos que no responde.

**Acción:** bloqueante. Nada se publica hasta resolverlo.

---

## 🟠 Altos — tratamiento real no declarado

| # | Qué falta | Evidencia |
|---|---|---|
| A1 | **Chat atleta ↔ PF**: mensajes de texto y archivos multimedia | `chats/{id}/messages`, `message.dart:24-25` (`text`, `mediaUrl`), `storage.rules:152` (`chatMedia/`) |
| A2 | **Resend** procesa tu email para el correo transaccional | `functions/src/mail/resend-client.ts`, `functions/src/auth/request-auth-email.ts` |
| A3 | **Google Places API** recibe tus búsquedas de gimnasio | `functions/src/places-search.ts` |
| A4 | **CARTO** recibe tu IP al cargar el mapa | `trainers_map_view.dart` → `https://{s}.basemaps.cartocdn.com/...` |
| A5 | **Push tokens y Crashlytics** | `firebase_messaging`, `firebase_crashlytics` en `pubspec.yaml` |
| A6 | **Feed y Rankings publican contenido a otros usuarios** — `PostPrivacy` tiene niveles (amigos / comunidad / público) y Rankings es opt-in por gimnasio | `post_privacy.dart`, `lib/features/gym_rankings/` |
| A7 | **`paymentAlias` del PF se publica** en el perfil público — es un identificador de cobro | `trainer_public_profile.dart:37` |

Ninguno aparece en la política vigente.

---

## 🟡 Medios

| # | Hallazgo | Detalle |
|---|---|---|
| M1 | **Analytics sin opt-out** | `main.dart:165` llama `setAnalyticsCollectionEnabled(true)` incondicionalmente, sin gate de `kReleaseMode`. La política lo menciona pero no ofrece cómo salir. Es además el pendiente abierto en `data-safety.md` |
| M2 | **Sin plazos de conservación** | «mientras mantengas tu cuenta» no es un plazo. Falta el detalle de qué sobrevive al borrado y por cuánto |
| M3 | **Sin transferencia internacional** | Firestore, Storage, Resend y Vercel corren fuera de Argentina. El art. 12 de la Ley 25.326 regula la transferencia internacional y exige base habilitante. No hay una línea al respecto |
| M4 | **La suscripción del PF no existe en los Términos** | `TIER_PRICES_ARS` ya define 12.000 / 22.000 / 39.000 ARS mensuales (`functions/src/subscriptions/tier-config.ts:56-58`). Los Términos no dicen que haya nada pago |
| M5 | **No se aclara que TREINO no intermedia los pagos alumno↔PF** | `payments/{id}` registra `amountArs` adeudado entre dos usuarios. Que TREINO no toque esa plata hay que decirlo, no darlo por obvio |
| M6 | **Sección 6 prohíbe acoso sin darle al usuario cómo denunciarlo** | Ver abajo |

---

## El hallazgo que no es un documento

**No existe mecanismo de reportar contenido ni de bloquear usuarios.**

Se buscó en todo `lib/` y `functions/src/`. Los únicos aciertos de «reportar»
son `exerciseFeedbackAction` — *«COMENTAR / REPORTAR una molestia»*, que es la
feature de dolor, no moderación. No hay reporte de posts, ni de reviews, ni de
mensajes, ni bloqueo de usuarios.

Al mismo tiempo la app tiene tres superficies de contenido generado por
usuarios: **feed** (`posts` con foto), **chat** (`messages` con multimedia) y
**reviews** (`reviews` con comentario libre).

La App Store Review Guideline 1.2 exige, para apps con UGC, cuatro cosas:
filtrado de material objetable, **mecanismo de reporte**, **capacidad de
bloquear usuarios abusivos**, y datos de contacto publicados. Es causal de
rechazo directo, y no se arregla con un documento — se arregla con producto.

→ Especificación en [`normas-de-comunidad.md`](./normas-de-comunidad.md).

---

## Lo que el borrador vigente sí hace bien

No todo está mal, y conviene no tirarlo:

- El **aviso de salud** (Términos, sección 3) existe y está bien orientado.
  Necesita endurecerse, no reescribirse.
- La **cláusula de PF independiente** (sección 5) apunta al riesgo correcto.
- El **habeas data** y la mención a la AAIP (Privacidad, sección 7) están bien
  encuadrados.
- La **ley aplicable** argentina es coherente con el resto del producto.
- La arquitectura de `LegalSection` + `LegalDocumentScreen` es buena: el
  documento se actualiza editando una lista, sin tocar la pantalla.

La estructura sirve. El contenido es el que no describe esta app.
