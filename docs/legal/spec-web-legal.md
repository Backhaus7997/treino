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

## 1. Estado actual — lo que hay y lo que falta

```
gettreino.com/legal/privacidad.html        404
gettreino.com/eliminar-cuenta              404
app.gettreino.com/legal/privacidad.html    200  OK
```

Las páginas legales **existen pero viven en el Coach Hub**
(`app.gettreino.com`), no en el sitio público. Se generan desde el repo de la
app con `dart run tool/build_legal_pages.dart` y viajan con `flutter build web`.

> ⚠️ **Bug en producción.** Esas páginas enlazan a `equipo@treino.app`, una
> casilla **que no existe**. Quien intente ejercer sus derechos o pedir el
> borrado de su cuenta por esa vía recibe un rebote. La casilla real es
> `treino@gettreino.com`. Hay que corregirlo en el repo de la app, no acá.

### 1.1 Decisión previa: dónde viven las páginas legales

Hay que elegir una y que sea consistente en las dos tiendas:

| Opción | Implica |
|---|---|
| **A — Servirlas desde `gettreino.com`** | El sitio público las aloja. Es lo más claro para el usuario y para los revisores de tienda. Hay que sincronizarlas o proxyearlas desde el repo de la app |
| **B — Dejarlas en `app.gettreino.com`** | Ya funciona. Pero el usuario que busca la política en el sitio público no la encuentra, y `/eliminar-cuenta` tiene que existir igual en la raíz |

**Recomendación: A.** El sitio institucional es donde se las busca, y el botón
de arrepentimiento tiene que estar sí o sí en la home de `gettreino.com`.

---

## 2. Footer legal — en todas las páginas

Bloque fijo al pie, presente en **todo** el sitio.

### 2.1 Identificación del titular

Obligatorio para comercio electrónico en Argentina. Texto sugerido:

> TREINO es un servicio de **BACKHAUSTIN S.A.S.** — CUIT 30-71929587-4
> Molino de Torres 5301, Córdoba Capital, Córdoba (CP 5021), Argentina
> treino@gettreino.com

### 2.2 Enlaces legales

| Texto del enlace | Destino |
|---|---|
| Política de Privacidad | `/legal/privacidad` |
| Términos y Condiciones | `/legal/terminos` |
| Normas de Comunidad | `/legal/comunidad` |
| Descargo Médico | `/legal/descargo-medico` |
| Términos para Entrenadores | `/legal/entrenadores` |
| Retención y eliminación de datos | `/legal/retencion` |
| Aviso Legal | `/aviso-legal` |
| **Eliminar mi cuenta** | `/eliminar-cuenta` |
| **Botón de Arrepentimiento** | `/arrepentimiento` |

Las dos últimas van **destacadas**, no perdidas entre las demás. Ver por qué
abajo.

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

| | Qué | Lo exige |
|---|---|---|
| ☐ | Footer con identificación del titular | Comercio electrónico AR |
| ☐ | Footer con los 9 enlaces legales | — |
| ☐ | Las páginas legales sirviéndose desde `gettreino.com` | Apple y Google |
| ☐ | **`/arrepentimiento`** enlazado desde la home | **Res. 424/2020** |
| ☐ | Formulario de arrepentimiento sin login | **Res. 424/2020** |
| ☐ | Correo automático con código en 24 h | **Res. 424/2020** |
| ☐ | **`/eliminar-cuenta`** en la raíz, sin login | **Google Play** |
| ☐ | Banner de cookies con rechazo visible | RGPD |
| ☐ | Inventario de terceros que carga el sitio | RGPD |
| ☐ | Precio final y condiciones antes de pagar | Defensa del consumidor |
| ☐ | Baja en línea | Res. 424/2020 |
| ☐ | Corregir `equipo@treino.app` → `treino@gettreino.com` | *(en el repo de la app)* |

---

## 9. De dónde sale el texto

Los textos legales **no se escriben acá**. Viven en `docs/legal/*.md` del repo
de la app y se generan:

```
docs/legal/*.md  ->  legal_content.dart  ->  web/legal/*.html
```

Si el rediseño necesita el contenido, se toma de ahí. **No copiar y pegar
manteniendo una segunda versión**: es exactamente el problema que esa cadena
vino a resolver.

Los documentos están en borrador y **no publicados**: esperan cuatro puntos de
revisión legal. Coordinar la publicación antes de linkearlos.
