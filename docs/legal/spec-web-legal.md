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
- **Edad mínima de cuenta: 13 años.**

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

### 1.1 El Botón de Arrepentimiento — re-verificación PENDIENTE

**No tratar esta tabla como un gate legal aprobado.** Los requisitos se
contrastaron contra la **Disposición 954/2025**, pero la transcripción literal de
su art. 1 no se pudo confirmar contra el Boletín Oficial (ver §3.1). Un texto que
no se leyó puede traer condiciones que no están acá.

Lo que la tabla dice es: de los requisitos **conocidos**, éstos se cumplen.

*(La verificación anterior decía «punto por punto» y era contra la Resolución
424/2020, **derogada** por el art. 10 de la 954/2025 — ver §3. Los requisitos
sobrevivieron a la derogación; lo que cambió es de dónde salen y cuánto se puede
afirmar sobre el chequeo.)*

| Requisito | Estado |
|---|---|
| Alcanzable desde la home | **Sí** — enlace en el pie, presente en la home |
| Texto sin ambigüedad | **Sí** — dice literalmente «Botón de Arrepentimiento» |
| Sin registración previa ni otro trámite | **Sí** — el formulario no pide iniciar sesión |
| «A simple vista … y en el primer acceso» | **No, y es una decisión tomada** — sigue en el pie. Ver §3.2 |
| Formulario con datos de la compra | **Sí** — nombre, correo, fecha, plan y notas |
| Informa el plazo | **Sí** — decía 14 días al verificarlo; el paso a 10 (decisión del 2026-09-25) no estaba desplegado al escribir esto |
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

**Lo exige la Disposición 954/2025** de la Subsecretaría de Defensa del
Consumidor y Lealtad Comercial (BO 4/9/2025), **modificada por la Disposición
3/2026** (BO 6/2/2026). Es un requisito argentino, y como la sociedad es
argentina y vende desde Argentina, está claramente alcanzada.

> ⚠️ **La Resolución 424/2020 está DEROGADA.** El art. 10 de la 954/2025 derogó
> las Resoluciones 316/2018 y 424/2020 y las reemplazó por un texto único. Este
> documento las citaba hasta el 2026-09-21; la verificación previa del botón
> estaba hecha contra una norma muerta. Los requisitos conocidos sobrevivieron
> casi iguales, así que **no hay motivo para creer que el botón haya dejado de
> cumplir por la derogación** — pero eso no es lo mismo que decir que cumple:
> falta re-verificar el art. 1 contra el texto original (§3.1). Y la 954/2025 trae
> **dos cosas que la 424/2020 no tenía**: el botón de baja (§3.5) y las
> exenciones del art. 3 (§3.6).

### 3.1 Lo que dice la norma

El **art. 1** obliga a los proveedores que venden a distancia por web o canal
digital a tener, **a simple vista, en lugar destacado y en el primer acceso**, un
link denominado **«BOTÓN DE ARREPENTIMIENTO»** para solicitar la revocación de la
compra o del servicio contratado. Agrega que al momento de usarlo el proveedor
**no podrá requerir registración previa ni ningún otro trámite adicional**.

> **Precisión.** Los arts. 3, 4 y 5 de abajo están transcriptos **literales** del
> texto publicado. El resto de este párrafo del art. 1 es una **descripción**, no
> una cita. Antes de apoyarse en su redacción exacta, leerlo en el Boletín
> Oficial.
>
> **Lo que sí está confirmado textual** (2026-09-21, contra el aviso del BO del
> 4/9/2025) es la frase de ubicación: **«a simple vista, en lugar destacado y en
> el primer acceso»**. Aparece idéntica en el art. 1 y en el art. 4 — y el art. 4
> ya estaba transcripto literal acá, así que las dos fuentes coinciden. Esa frase
> es la que decide §1.1 y §3.2, y por eso se verificó aparte.

#### El art. 5 — las 24 horas y el código, para LOS DOS botones

El plazo de respuesta **no sale del art. 1**: es un artículo aparte, y por eso
alcanza también al botón de baja del art. 4.

> «A partir de la solicitud de revocación de la aceptación **y/o de la solicitud
> de baja del servicio**, dentro de las VEINTICUATRO (24) horas subsiguientes y
> por el mismo medio, el proveedor deberá informar al consumidor el código de
> identificación […]»

Ese **«y/o de la solicitud de baja del servicio»** es el que cierra la pregunta:
las 24 horas con código **no son sólo del arrepentimiento**. Los dos botones
tienen que responder igual.

*(La cita está cortada en el cierre — de ahí el `[…]`. Lo que sigue al código de
identificación no se pudo confirmar. El fragmento citado sí, y es el que decide
el alcance.)*

**Fuentes:**

- [BO — Disposición 954/2025](https://www.boletinoficial.gob.ar/detalleAviso/primera/330827/20250904)
- [InfoLEG — texto 954/2025](https://servicios.infoleg.gob.ar/infolegInternet/anexos/415000-419999/417152/norma.htm)
- [BO — Disposición 3/2026](https://www.boletinoficial.gob.ar/detalleAviso/primera/338248/20260206)

### 3.2 Traducido a requisitos de implementación

| Requisito | Qué significa |
|---|---|
| **Desde la home** | Alcanzable desde `gettreino.com` en un click |
| **Sin login para LLEGAR** | Una persona sin sesión iniciada tiene que poder **abrir** el formulario. Ver el matiz de la 3/2026 abajo |
| **Sin pasos previos** | Nada de "primero ingresá a tu cuenta" ni menúes intermedios **antes** del link |
| **«A simple vista … y en el primer acceso»** | Ver el recuadro de abajo: el criterio cambió con la derogación y la ubicación actual es una decisión tomada, no un cumplimiento verificado |
| **Texto literal** | El enlace dice **"Botón de Arrepentimiento"**. Nada de "Gestión de suscripción" ni eufemismos: la norma pide que no deje dudas |

> ⚠️ **Los dos botones están en el pie —el de baja desde el 2026-09-21— y la
> norma vigente pide más que eso.** (Que estén publicados no quiere decir que
> funcionen: el canal que registra las solicitudes está caído en los dos. Eso
> es §3.5, y es más urgente que esto.)
>
> El criterio **cambió con la derogación**, y la conclusión vieja de este archivo
> se quedó sin fundamento sin que nada lo indicara:
>
> | | Texto |
> |---|---|
> | **Res. 424/2020** (derogada) | «link de acceso fácil y directo **desde la página de inicio**» |
> | **Disp. 954/2025**, arts. 1 y 4 | «**a simple vista, en lugar destacado y en el primer acceso**» |
>
> Bajo la redacción vieja, un enlace en el pie de la home cumple **literal**:
> está «desde la página de inicio». Por eso se puso ahí y por eso este archivo
> decía «el pie alcanza y es la práctica de mercado». Bajo «a simple vista … en
> el primer acceso», esa misma frase ya no describe algo que exige scrollear
> pasando el Hero y las ValueProps.
>
> Los arts. 1 y 4 usan la **misma** redacción: esto no es del botón de baja, el
> de arrepentimiento lo arrastra desde antes de que el otro existiera.
>
> **Decisión del 2026-09-21: se dejan en el pie.** La tomó Martín, con el texto
> de la norma y la alternativa —una franja fina sobre el Navbar— sobre la mesa.
> Mover los links cambia la primera pantalla de la landing en todas las páginas,
> y esa es una decisión de negocio, no de implementación.
>
> **Lo que NO hay que hacer con esto:** ni «arreglarlo» por iniciativa propia en
> un PR de otra cosa, ni volver a escribir que el pie alcanza. Queda como riesgo
> conocido y aceptado, a revisar con el abogado junto con los nueve documentos.
> Si la decisión se da vuelta, el lugar es el `Navbar` de `treino-app`
> (`fixed top-0 h-16`), y hay **11 lugares** que compensan su altura con
> `pt-24`/`pt-20`/`pt-16` — todos se tocan en el mismo PR o la landing queda con
> el contenido debajo del header.

#### El matiz de la Disposición 3/2026 — se puede verificar identidad

La 3/2026 complementa los arts. 1 y 4 de la 954/2025. Su art. 1 dice que el
consumidor

> «deberá cumplimentar los mecanismos o pasos previstos al efecto por el
> proveedor, siempre que estos sean **razonables**, a través de **medios
> habituales** y tengan por **finalidad exclusiva la verificación de identidad y
> seguridad** del usuario»

**Qué cambia en la práctica.** La prohibición de registración previa se lee sobre
el **acceso al botón**, no sobre todo el trámite. El link sigue teniendo que
estar público y alcanzable sin sesión; lo que viene **después** de tocarlo puede
pedir verificación de identidad, siempre que sea razonable y sólo para eso.

**Por qué importa acá y no es un detalle legal.** Un endpoint público y sin
autenticar que da de baja suscripciones es un canal de abuso: cualquiera puede
dar de baja la suscripción de otro con sólo saberle el correo. La 3/2026 habilita
exactamente el resguardo que ese diseño necesitaba. Leer la norma como «prohibido
verificar identidad» obliga a construir el agujero.

**Lo que NO habilita:** usar la verificación como traba. «Razonable», «medios
habituales» y «finalidad exclusiva» son tres condiciones, no una sugerencia. Un
flujo que exija crear cuenta, llamar por teléfono o subir documentación no entra.

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

- Que el plazo es de **10 días corridos** desde la contratación, y que si el
  último día cae en un día inhábil se extiende hasta el primer día hábil
  siguiente. *(Art. 34 de la Ley 24.240 y art. 1110 del CCyC. Decisión del
  titular del 2026-09-25: el piso legal. Antes decía 14 —«Argentina exige 10 y
  la Unión Europea 14; se adopta 14 para todos»—; ese motivo cayó con el
  lanzamiento acotado a la Argentina, ver `ESTADO.md`.)*
- Que dentro de ese plazo el reembolso es total.
- Que fuera de ese plazo se puede dar de baja igual, con acceso hasta el fin del
  período pagado, pero sin reembolso.
- **Si la suscripción se contrató desde la app por Apple o Google**, el
  reembolso lo gestiona la tienda y hay que dirigir al usuario a su flujo.

### 3.5 Botón de Baja de Servicio — el segundo botón

La 954/2025 trae un botón que la 424/2020 **no tenía**. Art. 4, literal:

> «Los proveedores que comercialicen bienes y servicios a distancia, a través de
> páginas web y/o canales digitales de comercialización o formato similar,
> deberán tener a simple vista, en lugar destacado y en el primer acceso, un link
> denominado **"BOTÓN DE BAJA DE SERVICIO"**, mediante el cual el consumidor
> pueda solicitar la baja del servicio contratado, con base en lo normado en el
> **Artículo 10 ter de la Ley N° 24.240** y sus modificatorias.
>
> Al momento de hacer uso del BOTÓN DE BAJA DE SERVICIOS, el proveedor no podrá
> requerir al consumidor registración previa ni ningún otro trámite adicional.»

**Es un botón distinto del de arrepentimiento**, con los mismos requisitos de
ubicación. No es lo mismo que `/es/eliminar-cuenta`, que es borrado de datos
personales (§4). Son tres cosas separadas.

**Plazo:** el art. 8 dio 60 días corridos para adecuarse. Exigible **desde el
2025-11-04**. Estamos fuera de plazo.

#### Esto NO es un requisito nuevo en este repo

Al actualizar la norma se descubrió que la tabla de pendientes del §8 ya listaba
**«Baja en línea del plan del entrenador»**, atribuida a la 424/2020. Es el mismo
requisito: lo que faltaba era el nombre que le pone la norma y el hecho de que
tiene que ser **un link público en el primer acceso**, no sólo un flujo alcanzable
estando adentro. Vale decirlo porque un análisis externo lo reportó como hallazgo
nuevo que agrandaba el alcance del release, y no lo es.

#### A quién alcanza en TREINO

Lo mismo que el arrepentimiento, y por el mismo motivo:

| Quién | Cómo paga | Quién gestiona la baja |
|---|---|---|
| **Profesor / entrenador** | Directo, Mercado Pago, desde el Coach Hub | **TREINO** — acá hace falta el botón |
| **Alumno** | Compra integrada (Apple / Google) | La **tienda**. El sitio indica la ruta, no ofrece el flujo |

#### Qué falta construir — actualizado el 2026-09-21

La **capacidad** ya existía (`cancelMySubscription` del lado del servidor y
`plan_cancel.dart` en el Coach Hub). La **puerta pública se construyó** en
`treino-app#15`, mergeado el 2026-09-21.

Estado de los cuatro puntos, **verificado contra producción**, no contra el
código:

| | Qué pedía | Estado |
|---|---|---|
| 1 | Link en el pie con el texto literal «Botón de Baja de Servicio» | ✅ `curl https://gettreino.com/es` lo devuelve |
| 2 | Su página, alcanzable **sin sesión iniciada** | ✅ `/es/baja-de-servicio` → `200` |
| 3 | Verificación de identidad detrás (habilitada por la 3/2026) | ⬜ **No se puso, a propósito.** El art. 4 prohíbe «otro trámite adicional»; la 3/2026 *permite* verificar, no obliga. Se pide nombre, correo, plan y canal, y la identidad la valida quien procesa |
| 4 | Respuesta en **24 h** con código de identificación (art. 5) | ❌ **BLOQUEADO** — ver abajo |

> 🚨 **El punto 4 no funciona, y tampoco funciona el del arrepentimiento.**
>
> Medido el 2026-09-21 contra producción:
>
> ```
> GET https://gettreino.com/api/baja-de-servicio  →  {"configured":false}
> GET https://gettreino.com/api/arrepentimiento   →  {"configured":false}
> ```
>
> El sumidero que registra las solicitudes **nunca se cargó en Vercel**. Las dos
> páginas se ven, los dos formularios se completan, y al enviar el servidor
> contesta `503`: no se registra nada, no se emite código y no sale ningún
> correo. El formulario deriva a `treino@gettreino.com` y le dice a la persona
> que su pedido cuenta desde hoy, que es lo único que se puede hacer sin el
> sumidero — pero eso es una red de contención, no el cumplimiento del art. 5.
>
> **Esto no se arregla con código, pero tampoco alcanza con cargar una variable.**
> Son **dos** pasos, y saltearse el primero deja la variable apuntando a la nada:
>
> 1. **Averiguar si el destino existe, y crearlo si no.** Al **2026-09-10** el
>    Apps Script que tiene que recibir las solicitudes **no existía**; si se creó
>    después, nadie lo registró acá. **Eso no se puede medir desde afuera**: el
>    `{"configured":false}` de arriba sólo prueba que la variable no está
>    cargada, y diría exactamente lo mismo con el script ya creado. Lo sabe
>    Martín, o se ve entrando al proyecto de Apps Script. El patrón es el que ya
>    usa la waitlist: escribe la fila en una planilla y manda el correo con el
>    código.
> 2. **Cargar `ARREPENTIMIENTO_WEBHOOK_URL` en Vercel** apuntando a ese script.
>    El endpoint de baja cae a esa misma variable a propósito, así que **con
>    cargar una andan los dos**.
>
> El paso 2 es el único confirmado con fecha de hoy. El 1 es un pendiente
> **probable**, no verificado — y la diferencia importa: si ya está hecho,
> esto se resuelve en cinco minutos de panel.
>
> La planilla recibe los dos trámites mezclados y se distinguen por el prefijo
> del código: `ARR-` contra `BAJA-`. Son trámites con efectos distintos —uno
> devuelve la plata, el otro no— así que quien procesa tiene que mirar el
> prefijo **antes** de actuar.
>
> Tener el botón visible y el canal muerto es peor que no tenerlo, porque la
> persona se va creyendo que hizo el trámite. Es lo más urgente de este archivo.

El **art. 8** dio 60 días para adecuarse: exigible desde el **2025-11-04**.

El punto 3 es lo que hace que esto sea chico: sin la 3/2026 habría que construir
un camino de baja público y anónimo, paralelo al que ya existe y sin forma de
saber quién pide la baja.

### 3.6 Las exenciones del art. 3 — leer antes de tocar el plazo

El art. 3 exime **del art. 1** (la obligación del botón de arrepentimiento) en
cuatro casos. Literal:

> «No regirá lo previsto en el Artículo 1° de la presente disposición, en los
> siguientes casos:
>
> a) En los casos establecidos en el Artículo 1.116 del Código Civil y Comercial
> de la Nación, excepto pacto en contrario.
>
> b) Cuando el consumidor **efectivamente haya utilizado o consumido** el producto
> o servicio contratado y, con posterioridad, pretenda ejercer el derecho de
> arrepentimiento dentro del plazo previsto en el Artículo 34 de la Ley N° 24.240
> y sus modificatorias.
>
> c) En el caso que el consumidor, sea persona humana o jurídica, pretenda
> ejercer el derecho de arrepentimiento respecto de la adquisición o contratación
> de productos o servicios con fines de reventa y/o sean integrados en procesos
> de producción, transformación, comercialización o prestación a terceros cuando
> se relacionen con dichos procesos, sea de manera genérica o específica,
> conforme lo establece el Artículo 2° del Decreto N° 1.798 de fecha 13 de
> octubre de 1994.
>
> d) Cuando se trate de la adquisición de productos perecederos.»

**El inciso b) es directamente relevante para TREINO**, que es una app que se usa
el mismo día que se paga. **Relevante no es «aplicable»**, y la diferencia no la
zanja este documento.

**Dos preguntas distintas, las dos abiertas:**

1. **¿Entrenar con la app cuenta como «efectivamente utilizado o consumido el
   servicio»?** Parece que sí en la lectura llana, pero «servicio» en una
   suscripción de tracto sucesivo no es lo mismo que un producto consumido, y el
   inciso no lo define. **Pregunta de abogado.**
2. **Si cuenta, ¿qué recorta?** El art. 3 exime de **lo previsto en el art. 1**,
   que es la obligación de tener el botón. Si eso además recorta el derecho de
   fondo del art. 34 de la Ley 24.240 —que es irrenunciable y no lo dicta esta
   disposición— **tampoco está contestado acá.**

Lo que sí queda establecido:

- La exención **existe** y su texto es el de arriba. Eso no es interpretación.
- El inciso a) remite al **art. 1116 CCyC «excepto pacto en contrario»**, así que
  el análisis del 1116 no es una rama independiente: la 954/2025 lo incorpora por
  referencia.
- El sustento escrito de «14 días» en `ESTADO.md` decía que el piso argentino son
  10 días. Ese piso sigue siendo el del art. 34, pero **la interacción con el
  inciso b) no está resuelta**. Ser más generoso que la ley siempre se puede: la
  decisión de negocio puede quedar igual. Lo que no se sostiene es el razonamiento
  tal como estaba escrito.
- *(2026-09-25)* El plazo ya no es más generoso que la ley: es el piso, 10 días
  corridos. La pregunta del inciso b) sigue abierta igual, y ahora pesa sobre si
  la ley obliga, no sobre el plazo: los 10 días están prometidos en los términos
  aunque la exención alcanzara a TREINO.

→ Va como pregunta al dictamen legal, con el texto citado.

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

La edad mínima de cuenta es **13 años**. Con ese piso COPPA no aplica, porque
alcanza a los menores de 13.

⚠️ **El art. 8 del RGPD NO queda cubierto con 13**: fija 16 como edad de
consentimiento digital y cada Estado miembro puede bajarla hasta 13, así que el
umbral varía por país. Con el lanzamiento acotado a la Argentina no es un
problema; **el día que se abra otro mercado hay que revisar esta sección**.

Sigue valiendo la cautela general: **no pedir más datos de los necesarios**, y no
pedir datos de salud en el sitio.

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
| ☐ | **Re-verificar el art. 1 de la 954/2025 contra el texto del Boletín Oficial.** Su transcripción literal no se pudo confirmar, así que la tabla del §1.1 cubre sólo los requisitos conocidos | **Disp. 954/2025 art. 1** |
| ☐ | Probar de punta a punta que el correo con el código llega en 24 h — **en LOS DOS botones** | **Disp. 954/2025 art. 5** |
| ☐ | Las seis páginas legales que faltan | Apple 1.2, consumidor |
| ☐ | Footer con identificación del titular (razón social, CUIT, domicilio) | Comercio electrónico AR |
| ☐ | Banner de cookies con rechazo tan visible como aceptar | RGPD |
| ☐ | Inventario de terceros que carga el sitio | RGPD |
| ☐ | Precio final y condiciones antes de pagar | Defensa del consumidor |
| ☐ | **«BOTÓN DE BAJA DE SERVICIO»** público para el plan del entrenador (§3.5) — *antes decía «Baja en línea», mismo requisito* | **Disp. 954/2025 art. 4** — fuera de plazo desde 2025-11-04 |
| ☐ | Cargar las URLs reales en App Store Connect y Play Console | Apple y Google |

> **Ojo con el alumno.** Su suscripción se cobra por compra integrada, así que
> la baja y el reembolso los gestionan Apple y Google. El sitio **no** tiene que
> ofrecerle un flujo de baja: tiene que indicarle la ruta de los ajustes de su
> dispositivo. El arrepentimiento del sitio es para el **entrenador**, que paga
> por Mercado Pago.
