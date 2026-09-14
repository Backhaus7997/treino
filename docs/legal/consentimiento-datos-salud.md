<!-- treino-legal
slug: consentimiento-salud
title: Consentimiento de datos de salud
dart: kHealthConsentSections
-->

# Consentimiento para el tratamiento de datos de salud

**Última actualización:** [[PENDIENTE — fecha de publicación]]
**Versión:** 1.0 (borrador)

> Documento con doble función: el **texto que se muestra al usuario** y la
> **especificación del flujo** que hay que construir. Hoy ese consentimiento no
> existe como acto separado — los datos de salud viajan bajo el consentimiento
> genérico del checkbox de Términos, que no alcanza.

---

## Por qué esto va aparte

El art. 2 de la Ley 25.326 define como **dato sensible** la información
referida a la salud. El art. 7 prohíbe recolectarlos salvo consentimiento
**expreso**, con finalidad determinada, y el art. 5 exige que ese
consentimiento sea **libre, expreso e informado**.

«Expreso e informado» quiere decir que la persona tiene que saber **qué dato
concreto** está entregando y **para qué**. Un checkbox que dice «acepto los
Términos y la Política de Privacidad», con la información de salud descripta
dentro de un documento de catorce secciones, no cumple ese estándar.

Y hay un agravante: la política vigente **ni siquiera menciona** que se
recolectan datos de salud. Es el hallazgo C1 de la
[auditoría](./AUDITORIA-legal-vigente.md).

---
---

# Parte A — El texto que ve el usuario

<!-- publish:start -->

## Tus datos de salud

TREINO puede guardar información sobre tu cuerpo y tu estado físico. Antes de
que cargues nada, queremos que sepas exactamente qué es y para qué se usa.

## Qué datos son

| Dato | Cuándo se guarda |
|---|---|
| **Peso y altura** | Si los cargás en tu perfil |
| **Medidas corporales** | Si las registrás: porcentaje de grasa, masa muscular, cintura, cadera, pecho, hombros, brazos, antebrazos, muslos, gemelos |
| **Molestias y dolores** | Cuando reportás una molestia en un ejercicio, **incluida la foto que adjuntes** |
| **Cómo te sentís** | Si hacés el check-in diario: tu ánimo, si tenés dolor y en qué zonas |
| **Tests de rendimiento** | Si registrás los resultados |
| **Plan de alimentación** | Si tu entrenador te arma uno |
| **Historial de entrenamiento** | Sesiones, ejercicios, series, pesos y repeticiones |

## Para qué los usamos

**Sólo para dos cosas:**

1. **Mostrarte tu propio progreso**: gráficos, evolución, estadísticas.
2. **Compartirlos con tu entrenador**, si vos lo habilitás.

**No los usamos para nada más.** No hay publicidad, no se venden, no se ceden a
terceros, no se usan para perfilarte ni para tomar decisiones automatizadas
sobre vos.

## Podés decir que no

**Podés usar TREINO sin cargar ningún dato de salud.** Vas a perder funciones
—el seguimiento de progreso, las estadísticas, el trabajo con un entrenador—
pero la aplicación funciona igual.

## Podés cambiar de opinión

- **Revocar este consentimiento** cuando quieras, desde Ajustes.
- **Dejar de compartir con tu entrenador** sin cortar el vínculo.
- **Borrar los datos** que cargaste.
- **Eliminar tu cuenta**, y con ella todo.

Revocar no borra lo ya cargado: para eso hay que pedir la supresión o
eliminarlo vos.

## Algo que quizá no imagines

Si te vinculás con un entrenador, **él puede llevar notas, un registro de
seguimiento y archivos sobre vos que no ves en tu aplicación**. Son datos
tuyos, y tenés derecho a pedirlos. Escribinos y te los entregamos.

## Dónde se guardan

En servidores de nuestros proveedores de infraestructura, **fuera de la
República Argentina**, cifrados en tránsito y con acceso restringido por reglas
que se evalúan en cada consulta.

---

> ☐ **Doy mi consentimiento expreso para que TREINO trate mis datos de salud y
> estado físico con las finalidades descriptas.**
>
> ☐ **Autorizo a compartir estos datos con el entrenador con el que me vincule.**
> *(opcional y revocable, se puede activar después)*

---

Responsable: **BACKHAUSTIN S.A.S.**, CUIT 30-71929587-4.
Más detalle en la [Política de Privacidad](./politica-de-privacidad.md).

---
---

<!-- publish:end -->

# Parte B — Especificación del flujo (no se publica)

## B.1 Estado actual

`UserProfile.termsAcceptedAt` registra una sola aceptación, que cubre Términos
y Privacidad en conjunto. Los datos de salud entran ahí adentro. **No hay
consentimiento específico, ni granular, ni revocable, ni versionado.**

## B.2 Campos a agregar en `users/{uid}`

| Campo | Tipo | Para qué |
|---|---|---|
| `healthDataConsentAt` | `Timestamp?` | Cuándo consintió el tratamiento |
| `healthDataConsentVersion` | `String?` | Qué versión del texto aceptó |
| `healthDataConsentRevokedAt` | `Timestamp?` | Si revocó, cuándo |

Reglas: escribibles sólo por el titular, y **la fecha no debe poder retrocederse**
desde el cliente — mismo criterio de pin que ya se usa con `acceptedAt` en
`trainer_links`.

El compartir con el entrenador **ya existe** (`sharedWithTrainer`,
`session_shares`, `profile_shares`) y no hay que rehacerlo: alcanza con
referenciarlo desde este flujo.

## B.3 Cuándo se pide

**No en el alta.** Pedirlo todo junto al registrarse es exactamente el error
que se quiere corregir: vuelve a ser un trámite que nadie lee.

Se pide **la primera vez que la persona va a cargar un dato de salud**, en el
momento en que tiene sentido:

| Disparador | Pantalla |
|---|---|
| Primera medición corporal | Registrar medición |
| Primer reporte de molestia | Sheet de «Comentar / Reportar» |
| Primer check-in diario | Check-in |
| Primer test de rendimiento | Registrar test |
| Al cargar peso o altura | Editor de perfil |

Una sola vez: consentido una, no se vuelve a pedir hasta que cambie la versión.

## B.4 Revocación

En **Ajustes → Privacidad**, con tres acciones separadas:

1. Revocar el consentimiento de datos de salud.
2. Dejar de compartir con el entrenador (ya existe).
3. Solicitar la supresión de los datos ya cargados.

Al revocar hay que decir con claridad qué se pierde, y ofrecer el borrado como
paso siguiente — revocar y borrar no son lo mismo y el usuario no tiene por qué
saberlo.

## B.5 Versionado

Si el texto cambia de forma relevante —nueva finalidad, nuevo dato, nuevo
destinatario— hay que **volver a pedirlo**. Sin `healthDataConsentVersion` no
hay forma de saber quién aceptó qué, y el consentimiento deja de ser probable.

## B.6 Qué NO hacer

- Meterlo en el mismo checkbox que los Términos.
- Bloquear la app entera si la persona dice que no. **El consentimiento tiene
  que ser libre**: si negarse deja la aplicación inutilizable, no es libre. Lo
  que corresponde es degradar la función, no el producto.
- Pedirlo una vez y no ofrecer nunca cómo salir.
