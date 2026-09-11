# Qué tiene que tener gettreino.com para cumplir

**Para:** quien rediseñe el sitio público.
**Verificado contra producción el 2026-09-03.**

Este documento se sostiene solo: no hace falta leer nada más para implementarlo.

---

## 0. Contexto mínimo

**TREINO** es una app de entrenamiento con una parte social y un espacio donde
entrenadores personales independientes ofrecen sus servicios. La opera:

| | |
|---|---|
| Razón social | **BACKHAUSTIN S.A.S.** |
| CUIT | 30-71929587-4 |
| Domicilio | Molino de Torres 5301, Córdoba Capital, Córdoba (CP 5021), Argentina |
| Contacto | **treino@gettreino.com** |
| Inscripción | Registro Público de Córdoba, Matrícula 46468-A |

Tres decisiones tomadas que condicionan todo lo de abajo:

- **Se vende a consumidores.** Suscripción para entrenadores, y a futuro para
  atletas.
- **Alcance mundial.**
- **Edad mínima de cuenta: 9 años.**

---

## 1. Estado actual — verificado en producción el 2026-09-10

**El sitio está internacionalizado con prefijo de idioma.** Las rutas legales
viven bajo `/es/`, no en la raíz. Cuatro ya están publicadas y funcionando:

| Ruta | Estado |
|---|---|
| `/es/arrepentimiento` | **200** — implementada |
| `/es/eliminar-cuenta` | **200** — implementada |
| `/es/privacidad` | **200** — implementada |
| `/es/terminos` | **200** — implementada |
| `/es/comunidad` | 404 |
| `/es/descargo-medico` | 404 |
| `/es/entrenadores` | 404 |
| `/es/suscripcion` | 404 |
| `/es/retencion` | 404 |
| `/es/aviso-legal` | 404 |
| `/es/cookies` | 404 |

### 1.1 El Botón de Arrepentimiento ya cumple

Se verificó contra la Resolución 424/2020, punto por punto:

| Requisito | Estado |
|---|---|
| Acceso desde la página de inicio | **Sí** — enlace en el pie, presente en la home |
| Texto sin ambigüedad | **Sí** — dice literalmente «Botón de Arrepentimiento» |
| Sin registración previa ni otro trámite | **Sí** — el formulario no pide iniciar sesión |
| Lugar destacado | **Sí** — pie de página, que es la práctica de mercado |
| Formulario con datos de la compra | **Sí** — nombre, correo, fecha, plan y notas |
| Informa el plazo | **Sí** — 14 días |
| Menciona el código de identificación | **Sí** |

**Lo único que no se puede verificar desde afuera es si el correo automático con
el código sale efectivamente dentro de las 24 horas.** Conviene probarlo de
punta a punta: enviar el formulario y confirmar que llega.

> ⚠️ **Bug pendiente, en el otro repositorio.** Las páginas legales que sirve el
> Coach Hub (`app.gettreino.com/legal/*`) enlazan a `equipo@treino.app`, una
> casilla **que no existe**. La real es `treino@gettreino.com`. Se corrige en el
> repo de la app, no acá.

## 2. Footer legal — en todas las páginas

Bloque fijo al pie, presente en **todo** el sitio.

### 2.1 Identificación del titular

Obligatorio para comercio electrónico en Argentina. Texto sugerido:

> TREINO es un servicio de **BACKHAUSTIN S.A.S.** — CUIT 30-71929587-4
> Molino de Torres 5301, Córdoba Capital, Córdoba (CP 5021), Argentina
> treino@gettreino.com

### 2.2 Enlaces legales

| Texto del enlace | Destino | Estado |
|---|---|---|
| Política de Privacidad | `/es/privacidad` | Publicada |
| Términos y Condiciones | `/es/terminos` | Publicada |
| **Botón de Arrepentimiento** | `/es/arrepentimiento` | Publicada |
| **Eliminar mi cuenta** | `/es/eliminar-cuenta` | Publicada |
| Términos de Suscripción | `/es/suscripcion` | **Falta** |
| Normas de Comunidad | `/es/comunidad` | **Falta** |
| Descargo Médico | `/es/descargo-medico` | **Falta** |
| Términos para Entrenadores | `/es/entrenadores` | **Falta** |
| Retención y eliminación de datos | `/es/retencion` | **Falta** |
| Aviso Legal | `/es/aviso-legal` | **Falta** |

El arrepentimiento y la eliminación de cuenta van **destacados**, no perdidos
entre los demás.

> **Nota sobre el prefijo `/es/`.** Con alcance mundial el sitio va a servir más
> idiomas. Las URLs que se carguen en App Store Connect y Play Console tienen que
> ser las reales, con prefijo — y conviene que sean estables, porque cambiarlas
> después obliga a actualizar las dos consolas.

---

## 3. Botón de Arrepentimiento

**Lo exige la Resolución 424/2020 de la Secretaría de Comercio Interior.** Es un
requisito argentino, y como la sociedad es argentina y vende desde Argentina,
está claramente alcanzada.

### 3.1 Lo que dice la norma, textual

> «deberá ser un link de acceso **fácil y directo desde la página de inicio**
> del sitio de Internet institucional de los sujetos obligados y ocupar un
> **lugar destacado, en cuanto a visibilidad y tamaño**, no dejando lugar a
> dudas respecto del trámite seleccionado»

> «Al momento de hacer uso del Botón, el proveedor **no podrá requerir al
> consumidor registración previa ni ningún otro trámite**»

### 3.2 Traducido a requisitos de implementación

| Requisito | Qué significa |
|---|---|
| **Desde la home** | Alcanzable desde `gettreino.com` en un click |
| **Sin login** | Una persona sin sesión iniciada tiene que poder completarlo |
| **Sin pasos previos** | Nada de "primero ingresá a tu cuenta" ni menúes intermedios |
| **Destacado** | El pie de página alcanza y es la práctica de mercado. No puede estar detrás de un acordeón ni en una página de tercer nivel |
| **Texto literal** | El enlace dice **"Botón de Arrepentimiento"**. Nada de "Gestión de suscripción" ni eufemismos: la norma pide que no deje dudas |

### 3.3 El formulario en `/arrepentimiento`

Campos mínimos:

- Nombre y apellido
- Correo electrónico de la cuenta
- Identificación de la compra: fecha aproximada y plan contratado
- Campo libre, opcional

Al enviar:

1. Mensaje en pantalla confirmando que se recibió.
2. **Correo automático al usuario dentro de las 24 horas** con un **código de
   identificación del arrepentimiento**. Esto lo pide la norma explícitamente,
   no es opcional.
3. Aviso interno a `treino@gettreino.com` para procesarlo.

El reembolso en sí **se hace a mano** desde el panel de la pasarela de pago. No
hace falta automatizarlo.

### 3.4 Qué explicar en esa página

- Que el plazo es de **14 días** desde la contratación. *(Argentina exige 10 y
  la Unión Europea 14; se adopta 14 para todos y así una sola regla cumple en
  todas partes.)*
- Que dentro de ese plazo el reembolso es total.
- Que fuera de ese plazo se puede dar de baja igual, con acceso hasta el fin del
  período pagado, pero sin reembolso.
- **Si la suscripción se contrató desde la app por Apple o Google**, el
  reembolso lo gestiona la tienda y hay que dirigir al usuario a su flujo.

---

## 4. Eliminación de cuenta — `/eliminar-cuenta`

**Google Play lo exige** para toda app que permita crear cuentas: tiene que
existir una URL **alcanzable desde un navegador, sin instalar la app**.

- Va en la **raíz**, no bajo `/legal`. Enterrarla es motivo de rechazo.
- Sin login.
- Explica qué se elimina, qué se conserva y por cuánto. El contenido sale de
  `docs/legal/retencion-y-borrado.md`.
- Formulario o instrucción clara de contacto a `treino@gettreino.com`.

---

## 5. Cookies y consentimiento

Con **alcance mundial** entran las reglas europeas:

- **Consentimiento previo** antes de cargar cualquier cosa no esencial:
  analítica, píxeles, embebidos de terceros.
- Opción de **rechazar tan visible como la de aceptar**. Nada de "Aceptar" en
  botón grande y "Preferencias" en link chiquito.
- Poder cambiar la elección después.
- Página `/legal/cookies` con el detalle de qué se usa y para qué.

> **Ojo con lo que carga el sitio.** Todo servicio de terceros que aparezca —
> analítica, mapas, tipografías remotas, chat, formularios embebidos — es un
> tratamiento de datos que hay que declarar. Conviene hacer el inventario
> durante el rediseño, que es cuando se sabe qué entra.

---

## 6. Si el sitio vende

Antes del pago hay que mostrar, sin que el usuario tenga que buscarlo:

- **Precio final**, con impuestos incluidos y moneda indicada.
- **Qué incluye** el plan y por cuánto tiempo.
- **Si se renueva solo**, cada cuánto y cómo se da de baja.
- Enlace a Términos y a Privacidad **antes** de confirmar.
- La **baja en línea** tiene que poder hacerse por el sitio, sin llamar ni
  mandar mail.

---

## 7. Menores

La edad mínima de cuenta es **9 años**. Si el sitio recolecta cualquier dato
—un formulario de contacto, una newsletter— hay que contemplar que quien lo
complete puede ser menor. El régimen aplicable lo está definiendo el asesor
legal; **consultarlo antes de sumar cualquier formulario que capture datos.**

---

## 8. Checklist

Hecho:

| | Qué |
|---|---|
| ✅ | `/es/arrepentimiento` enlazado desde el pie de la home, sin login |
| ✅ | Formulario de arrepentimiento con datos de la compra |
| ✅ | `/es/eliminar-cuenta` publicada |
| ✅ | `/es/privacidad` y `/es/terminos` publicadas |

Pendiente:

| | Qué | Lo exige |
|---|---|---|
| ☐ | Probar de punta a punta que el correo con el código llega en 24 h | **Res. 424/2020** |
| ☐ | Las seis páginas legales que faltan | Apple 1.2, consumidor |
| ☐ | Footer con identificación del titular (razón social, CUIT, domicilio) | Comercio electrónico AR |
| ☐ | Banner de cookies con rechazo tan visible como aceptar | RGPD |
| ☐ | Inventario de terceros que carga el sitio | RGPD |
| ☐ | Precio final y condiciones antes de pagar | Defensa del consumidor |
| ☐ | Baja en línea del plan del entrenador | Res. 424/2020 |
| ☐ | Cargar las URLs reales en App Store Connect y Play Console | Apple y Google |

> **Ojo con el alumno.** Su suscripción se cobra por compra integrada, así que
> la baja y el reembolso los gestionan Apple y Google. El sitio **no** tiene que
> ofrecerle un flujo de baja: tiene que indicarle la ruta de los ajustes de su
> dispositivo. El arrepentimiento del sitio es para el **entrenador**, que paga
> por Mercado Pago.
