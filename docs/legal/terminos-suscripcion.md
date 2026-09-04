<!-- treino-legal
slug: suscripcion
title: Términos de Suscripción
dart: kSubscriptionSections
-->

# Términos de Suscripción de TREINO

**Última actualización:** [[PENDIENTE — fecha de publicación]]
**Versión:** 1.0 (borrador)

> ⚠️ **BORRADOR.** Complementa los [Términos y
> Condiciones](./terminos-y-condiciones.md). Para entrenadores rigen además los
> [Términos para Entrenadores](./contrato-entrenador.md).

<!-- publish:start -->

## 1. Qué se paga y qué no

**Usar TREINO como atleta es gratuito.** Registrar entrenamientos, seguir tu
progreso, participar del feed y vincularte con un entrenador no tienen costo.

**Los entrenadores** requieren una suscripción para atender alumnos por encima
del límite del plan gratuito.

Está prevista una **suscripción para atletas** a futuro. Cuando exista te
informaremos sus condiciones, y **no se te cobrará nada sin tu consentimiento
expreso**.

Los pagos entre un alumno y su entrenador **no pasan por TREINO** y no están
alcanzados por este documento. Ver la sección 7 de los Términos y Condiciones.

## 2. Planes para entrenadores

| Plan | Alumnos | Por mes | Por año |
|---|---|---|---|
| Gratuito | 2 | — | — |
| Plan 1 | 7 | $12.000 | $120.000 |
| Plan 2 | 15 | $22.000 | $220.000 |
| Plan 3 | Sin límite | $39.000 | $390.000 |

Precios en pesos argentinos, con impuestos incluidos. El plan anual equivale a
diez meses.

Un alumno **pausado ocupa media plaza** y uno activo una entera. El detalle está
en la sección 8.2 de los Términos para Entrenadores.

## 3. Cómo se cobra

Los pagos se procesan a través de un **proveedor de servicios de pago externo**,
que captura el medio de pago y liquida los fondos a la cuenta bancaria de
BACKHAUSTIN S.A.S.

**TREINO no almacena los datos completos de tu tarjeta ni de tu medio de pago.**
Quedan en poder de ese procesador, que es responsable de su propio tratamiento.

Antes de confirmar cualquier contratación vas a ver el **precio final**, la
moneda, qué incluye el plan, cada cuánto se renueva y cómo darlo de baja.

## 4. Período de prueba

Los planes pagos pueden ofrecerse con un **período de prueba gratuito**. Durante
ese período no se cobra nada.

**Si das de baja antes de que termine, no se te cobra.** Si no lo hacés, al
finalizar comienza el primer período pago, con aviso previo.

## 5. Renovación automática

Las suscripciones **se renuevan automáticamente** al final de cada período —
mensual o anual, según el plan que hayas elegido— salvo que las des de baja
antes.

Te avisamos antes de cada renovación y antes de cualquier cambio de precio. Si
el precio cambia, podés dar de baja sin penalidad antes de que entre en
vigencia.

## 6. Tu derecho a arrepentirte

**Tenés 14 días corridos desde la contratación para arrepentirte y recuperar
todo lo pagado, sin dar explicaciones y sin costo alguno.**

Adoptamos 14 días **para todo el mundo**. Es más de lo que exige la ley
argentina —que son 10— y equivale al plazo europeo, así que la misma regla te
cubre vivas donde vivas.

### Cómo ejercerlo

Desde el **Botón de Arrepentimiento**, disponible en la página principal de
gettreino.com. **No necesitás tener la sesión iniciada ni hacer ningún trámite
previo.**

Dentro de las **24 horas** te enviamos por el mismo medio un **código de
identificación** de tu pedido, y a continuación te devolvemos el dinero por el
mismo medio de pago.

Este derecho es **irrenunciable**: nada de lo que digan estos términos puede
quitártelo.

## 7. Baja fuera del plazo de arrepentimiento

Pasados los 14 días **podés dar de baja cuando quieras**, en línea, sin llamar
ni escribir a nadie.

Al hacerlo:

- **Conservás el acceso hasta el final del período que ya pagaste.**
- **No se reembolsa el período en curso.**
- No se te vuelve a cobrar.

## 8. Si contrataste desde la aplicación

Si tu suscripción se contrató a través de App Store o Google Play, **la baja y
el reembolso los gestiona la tienda** conforme a sus propias políticas, y no
podemos procesarlos nosotros.

En ese caso tenés que gestionarlo desde los ajustes de suscripciones de tu
dispositivo. Te indicamos dónde en el momento de la baja.

## 9. Si no pagás

Si un pago queda impago, tu plan pasa al límite del plan gratuito y algunos de
tus vínculos con alumnos quedan bloqueados.

**Tus alumnos no pierden nada:** conservan sus rutinas, su historial, sus datos y
su chat. Al regularizar, los vínculos se reactivan hasta el límite de tu plan.

## 10. Facturación

Emitimos el comprobante que corresponda según la normativa aplicable. Los
registros de pago entre vos y tus alumnos que lleva la aplicación **no son
comprobantes fiscales**.

## 11. Contacto

**BACKHAUSTIN S.A.S.** — CUIT 30-71929587-4
Molino de Torres 5301, Córdoba Capital, Provincia de Córdoba (CP 5021), Argentina
treino@gettreino.com

<!-- publish:end -->

---

# Anexo — Implementación (no se publica)

## A. Lo que hay que construir

| # | Qué | Dónde | Bloquea |
|---|---|---|---|
| 1 | **Botón de Arrepentimiento** en la home, sin login | `gettreino.com` | **Sí, si se cobra** |
| 2 | Formulario de arrepentimiento | `gettreino.com/arrepentimiento` | **Sí** |
| 3 | **Correo automático con código dentro de 24 h** | Backend | **Sí** |
| 4 | Baja en línea | Coach Hub web | **Sí** |
| 5 | Aviso previo a renovación y a cambio de precio | Backend | Sí |
| 6 | Pantalla de precio final antes de confirmar | Coach Hub web | Sí |

Especificación completa del sitio en [`spec-web-legal.md`](./spec-web-legal.md).

**El reembolso se opera a mano** desde el panel de la pasarela. La norma exige un
proceso, no un sistema automatizado, y con el volumen esperado alcanza.

## B. Lo que todavía no está resuelto

[[PENDIENTE — REVISIÓN LEGAL. Tres puntos: (a) si los bienes digitales
consumidos dentro de la app obligan a usar el sistema de pago de la tienda
—regla 3.1.1 de Apple y política de facturación de Google—, lo que cambiaría
quién gestiona bajas y reembolsos y hay que resolver ANTES de construir la
integración; (b) si algún supuesto del art. 1116 del Código Civil y Comercial
excluye a un servicio por suscripción del derecho de revocación, y si es
oponible una renuncia expresa a cambio de ejecución inmediata como admite el
régimen europeo; (c) tratamiento fiscal de servicios digitales en cada mercado
donde se cobre.]]

## C. Estado del código

El paywall existe (`functions/src/subscriptions/`), con tabla de precios y
límites por plan. **No hay procesador de pagos integrado**, y el enforcement del
lado del entrenador está pendiente. Nada de lo de arriba está construido.
