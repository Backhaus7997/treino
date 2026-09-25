# Estado del trabajo legal y de moderación

**Última actualización:** 17 de septiembre de 2026
**Alcance:** todo lo trabajado entre el 31 de agosto y el 17 de septiembre.

Este documento se sostiene solo. Sirve para retomar el tema sin leer ninguna
conversación previa, y para pasárselo a otra persona.

---

## Dónde estamos, en una línea

**La redacción legal está cerrada y el generador está a un solo marcador.** Los
once marcadores de revisión legal se resolvieron con investigación de fuentes
primarias, sin esperar al abogado. La edad mínima quedó en **13**, el age gate se
mergeó (#1162) y el barrido de retención se encendió el 17/09 después de medir
que no hay backlog. **El único marcador que queda es el INPI.**

Lo que bloquea publicar hoy son **dos cosas de código, una de la landing y dos de
trámite**: el filtrado de términos vetados, la vista de revisión de reportes, las
páginas legales de `gettreino.com`, la inscripción ante la AAIP y el registro de
marca.

⚠️ **El alcance se acotó a la Argentina el 17/09.** Con eso se cayeron el
representante en la Unión Europea, el del Reino Unido y todo el paquete de
Estados Unidos. No es un olvido: es una decisión, y el día que se abra otro
mercado hay que volver a esta lista.

---

## 1. El titular

| | |
|---|---|
| Razón social | **BACKHAUSTIN S.A.S.** |
| CUIT | 30-71929587-4 |
| Sede social | Molino de Torres 5301, Córdoba Capital, Córdoba (CP 5021) |
| Matrícula | 46468-A — Registro Público de Córdoba |
| Constitución | 23/01/2026, Ley 27.349 |
| Contacto legal | **treino@gettreino.com** |

El dominio es **gettreino.com**. `treino.com` está registrado desde 2005 por un
tercero y **no es nuestro**; las apariciones en el repo son URLs falsas de un
mockup de diseño.

---

## 2. Las seis decisiones, todas tomadas

| # | Decisión | Qué se resolvió |
|---|---|---|
| D1 | **Titular** | BACKHAUSTIN S.A.S., sociedad constituida |
| D2 | **Edad mínima** | **13 años** (2026-09-17; antes 16, antes 9), con consentimiento del representante legal para todo menor de 18 |
| D3 | **Alcance** | **Mundial** |
| D4 | **Cobro** | Mixto: entrenador por Mercado Pago en la web, atleta por compra integrada |
| D5 | **Alumno ↔ PF** | TREINO **no intermedia** esa plata. Sólo registra la deuda |
| D6 | **Reembolsos** | **10 días corridos**, el piso legal, para todo el mundo (2026-09-25; antes 14) |

Más una séptima, posterior:

**Las cuentas de tienda quedan a nombre personal** (Martin Backhaus), no de la
sociedad. Decisión del titular con los argumentos en contra sobre la mesa. Se
cae el trámite del D-U-N-S, que era el de mayor plazo del proyecto.

### Por qué 10 días

**Decisión del titular, 2026-09-25: el plazo de arrepentimiento pasa a ser el
piso legal, 10 días corridos, para los dos planes.** Reemplaza a la de los 14
días del 2026-09-21, que queda abajo como historia.

La base, verificada contra las fuentes primarias el 2026-09-25:

- **Ley 24.240, art. 34:** «DIEZ (10) días corridos contados a partir de la
  fecha en que se entregue el bien o se celebre el contrato».
- **Código Civil y Comercial, art. 1110:** «dentro de los diez días computados
  a partir de la celebración del contrato», y si el plazo vence en un día
  inhábil se prorroga hasta el primer día hábil siguiente.

Esa prórroga **se escribió en los textos** donde se le explica el plazo al
usuario (Términos de Suscripción §6, Términos y Condiciones §8, Términos para
Entrenadores §8.4, y la página `/es/arrepentimiento` de la landing). Con 14 días
no hacía falta decirla —el margen la tapaba—; con el piso exacto, sí.

**Todo lo demás queda igual:** reembolso de todo lo pagado, sin dar
explicaciones, sin costo, sin excepciones, sin iniciar sesión, desde
`gettreino.com/es/arrepentimiento`. El derecho sigue siendo irrenunciable.

**A qué contratos aplica.** A los que se celebren desde la fecha de los
términos nuevos (la «Última actualización» que estampa el generador). Quien
haya contratado mientras se publicaban 14 días contrató con esa promesa, y lo
prudente es honrársela. Según las notas del equipo, al 2026-09-24 todavía no se
había cobrado ninguna suscripción por la web, así que no habría nadie en ese
caso — **eso no está verificado contra producción al 2026-09-25**. Antes de
publicar, alguien tiene que mirarlo en Mercado Pago.

**Lo que este cambio NO hizo:** no bumpeó `version` de los Términos y
Condiciones (el entero que se sella en `acceptedTermsVersion`), así que el
cambio no dispara una nueva aceptación. Si hace falta que quien ya aceptó vuelva
a aceptar, es decisión aparte.

### Historia: por qué eran 14 días y no 10 (2026-09-21, reemplazada el 2026-09-25)

**Decisión del titular, 2026-09-21: se mantienen los 14 días para los dos
planes.** Argentina exige 10 corridos (art. 34 de la Ley 24.240) y damos cuatro
más. El derecho es **irrenunciable**: una cláusula que diga «no hay reembolsos»
se tiene por no escrita y se aplica la ley igual.

El motivo anterior decía que con 14 «una sola regla cumple en todas partes»,
porque 14 era el plazo europeo. **Ese argumento ya no aplica**: con el
lanzamiento acotado a la Argentina (2026-09-17) hay un solo mercado, así que no
hay dos plazos que unificar. La política no cambió; el motivo sí, y ahora es
simplemente que ser más generoso que el piso legal no hay que defenderlo ante
nadie.

> ⚠️ **Este razonamiento quedó incompleto (2026-09-21).** Citaba la Resolución
> 424/2020, **derogada** por el art. 10 de la Disposición 954/2025. La que la
> reemplaza trae una exención que la vieja no tenía: su **art. 3 inciso b)** exime
> «cuando el consumidor efectivamente haya utilizado o consumido el producto o
> servicio contratado». TREINO es una app que se usa el mismo día que se paga, así
> que el inciso es **directamente relevante**.
>
> **Qué NO se concluye de esto — dos preguntas abiertas, no una.** Primera: si
> entrenar con la app cuenta como «efectivamente utilizado o consumido» tratándose
> de una suscripción de tracto sucesivo. Segunda: si contara, el art. 3 exime de
> lo previsto en el art. 1 —la obligación de tener el botón—, y si además recorta
> el derecho de fondo del art. 34, que es irrenunciable y no lo dicta esta norma,
> tampoco está resuelto. **Las dos son pregunta de abogado.**
>
> La decisión de negocio de mantener 14 días puede quedar igual: ser más generoso
> que la ley siempre se puede. Lo que ya no se sostiene es el sustento tal como
> está escrito arriba.
>
> → Detalle y texto citado en [spec-web-legal.md §3.6](./spec-web-legal.md).

### Por qué el cobro quedó mixto

No es preferencia, es la única puerta abierta. La Guideline 3.1.3(f) de Apple
exime del pago integrado a una *«free app acting as a stand-alone companion to a
paid web based tool»*, y el Coach Hub **es** esa herramienta. Para el atleta no
existe superficie web, así que no hay exención que invocar y cae 3.1.1.

El razonamiento vive en `lib/features/paywall/application/athlete_checkout.dart`.

### La consecuencia de las cuentas personales

Los trece documentos dicen que el responsable es BACKHAUSTIN S.A.S. y la ficha
de la tienda dirá «Martin Backhaus». Se resolvió **declarando la relación** en el
Aviso Legal en vez de esconderla: quien publica actúa por cuenta de la sociedad,
y eso no desplaza la responsabilidad del servicio.

Queda abierto, y **es tema del contador, no del abogado**: las tiendas liquidan
a la persona mientras la sociedad factura. Con la suscripción del atleta ya
cobrando por compra integrada, esa plata ya está entrando al CUIT equivocado.

---

## 3. Lo construido

### PR #1094 — Documentos legales

Trece archivos en `docs/legal/`. Diez son documentos, más la auditoría, el
briefing para el abogado y el spec para el rediseño del sitio.

**No están escritos contra una plantilla, sino contra el código y las reglas de
Firestore.** Esa es la diferencia que los hace exactos.

También trae:

- `scripts/build_legal_content.py` — genera `legal_content.dart` desde los
  markdown. **Aborta si queda un `[[PENDIENTE]]`** en texto publicable.
- Gate en `ci.yml` que rompe el PR si alguien edita un markdown y no regenera.
- **Perfil → Legales** — hasta ahora los legales sólo se alcanzaban desde el
  registro, o sea que con la cuenta creada **nadie podía releer lo que aceptó**.

La cadena de publicación quedó así:

```
docs/legal/*.md  ->  legal_content.dart  ->  web/legal/*.html
```

Cada eslabón con su guarda: el gate de CI compara markdown contra Dart, y
`paginas_legales_sync_test` compara Dart contra HTML.

### PR #1114 — Reportar y bloquear

El requisito de la **App Store Review Guideline 1.2**. Colecciones `blocks` y
`reports`, enforcement en reglas, y entrada en las cuatro superficies: feed,
chat, reseñas y perfil público.

**41 tests de reglas nuevos**, corridos contra el emulador real, con foco
negativo.

---

## 4. Los hallazgos que más importan

### El error de diseño que se evitó a tiempo

El instinto era sumar `notBlocked()` al `allow read` de `posts`. **Eso rompe el
feed entero.**

En Firestore las reglas de `list` se evalúan contra la query, y si un solo
documento del resultado no pasa, **se rechaza toda la query en vez de filtrar la
fila**. `feedPublic()` no filtra por autor, así que el primer post de alguien con
quien exista un bloqueo dejaría el feed **en blanco**. Y el bug aparecería recién
el día que alguien bloquee a alguien: en producción.

Está documentado en el propio repo, en `post_providers.dart:157`.

**La solución:** el bloqueo se hace cumplir en la **escritura** —chat,
reacciones, follows, reseñas—, que es donde está el daño real. A alguien acosado
lo protege que el otro no lo pueda contactar, no que no pueda leer un post
público.

Y un efecto de arrastre: **bloquear borra las aristas de follow en las dos
direcciones**, con lo cual el tier `followers` queda protegido por la regla que
ya existía, sin tocar una línea.

### El bug que casi se publica

`Block.toJson()` incluía `id`, copiando el patrón de `Follow` —que sí lo
necesita—. Pero el `hasOnly` de las reglas **no** lo incluye.

Sin el fix, bloquear y reportar habrían fallado **siempre** con
`PERMISSION_DENIED`. Invisible para los tests de widget, porque usan mocks.

### Lo que la auditoría encontró en el texto que ya estaba publicado

18 hallazgos sobre `legal_content.dart`. Los cinco críticos:

1. **La política no mencionaba datos de salud**, y la app recolecta siete tipos:
   más de veinte medidas corporales, dolores reportados **con foto**, check-in
   diario de ánimo y dolor, planes de alimentación, tests de rendimiento. Eso ya
   estaba declarado ante Google en `store/privacy/data-safety.md` — se le había
   dicho a la tienda y no al usuario.
2. **«Tu ubicación no es visible para otros usuarios» era falso** para el
   entrenador. (Ya corregido por el PR #941.)
3. **El entrenador lleva notas, seguimiento y archivos sobre el alumno que el
   alumno nunca ve.** Son datos personales suyos y el derecho de acceso los
   alcanza igual.
4. **La cláusula de edad no se podía cumplir**: decía 16 años y el sistema nunca
   verificó la edad.
5. **El responsable no estaba identificado**, y el contacto publicado
   (`equipo@treino.app`) era un buzón inexistente. (Ya corregido.)

---

## 5. Lo que falta

### Bloquea publicar

| # | Qué | De quién | Estado |
|---|---|---|---|
| 1 | ~~Mergear los dos PRs~~ | Equipo | **HECHO** |
| 2 | ~~Política multi-jurisdicción~~ — bases legales por finalidad, transferencias, portabilidad, oposición, plazos de incidente | Redacción | **HECHO** el 2026-09-16 |
| 3 | ~~Consentimiento parental **verificable**~~ | — | **NO HACE FALTA** con el piso en 13: COPPA alcanza a menores de 13. El consentimiento del representante **declarado** sí se pide, para todo menor de 18 |
| 4 | ~~**Age gate en el alta**~~ — `bornAt` pasó a ser obligatorio y se pide en el paso 2 del alta; el router manda a `/birth-date` a las cuentas anteriores, y las reglas de Firestore validan el piso en `create` y en `update` | Desarrollo | **HECHO** — PR #1162, mergeado el 2026-09-17 |
| 5 | **Filtrado de términos vetados** — cuarto requisito de la Guideline 1.2, el único que #1114 no cubre | Desarrollo | Pendiente |
| 6 | **Vista de revisión de reportes** — ver la sección 6 | Desarrollo | Pendiente |
| 7 | **Páginas legales en la landing** — con los marcadores cerrados ya no hay documento bloqueado por texto | Desarrollo | Especificado |
| 8 | ~~**Encender el barrido de retención**~~ | Titular | **HECHO** el 2026-09-17. El backlog se midió por dos caminos independientes y dio **cero**: a la cuenta más inactiva le faltan 601 días para el umbral de aviso. Ver §8.1 de `retencion-y-borrado.md` |
| 9 | ~~Representante en la Unión Europea y en el Reino Unido~~ | Titular | **FUERA DE ALCANCE** desde el 17/09, con el lanzamiento acotado a la Argentina. El art. 27 del RGPD los exige y las excepciones del 27(2) no aplican —el tratamiento de datos de salud es continuo y a gran escala—, así que **son obligatorios el día que se abra la Unión Europea**, y hay que publicar su identidad y contacto en la política |
| 11 | **Registro de marca ante el INPI** — es el último marcador vivo del generador. Con presentar la solicitud alcanza: el número sale el mismo día y el aviso legal puede decir "en trámite" | Titular | Pendiente |
| 10 | **Dictamen legal** — las siete preguntas, ahora para validar lo ya resuelto en vez de destrabar | Abogado | No bloquea |

### Trámites

- **Inscribir la base de datos ante la AAIP.**
- **Probar el arrepentimiento de punta a punta** desde el formulario real.
- Cargar las URLs legales en App Store Connect y Play Console. Las reales llevan
  prefijo de idioma: `/es/privacidad`, `/es/terminos`, `/es/arrepentimiento`,
  `/es/eliminar-cuenta`.
- *(Ya no hace falta: D-U-N-S ni conversión de cuentas.)*

### Deuda registrada, no bloqueante

- **Analytics sin opt-out** — se activa incondicionalmente en `main.dart:172` y
  en el Coach Hub.
- **Bloqueos huérfanos al borrar cuenta** — la cascada borra por campo
  `athleteId` y `blocks`/`reports` llevan los uids en el id, así que no los
  alcanza.
- **Moderación de imágenes.**
- **Política de cuentas inactivas** — hoy una cuenta sin uso conserva sus datos
  indefinidamente.

---

## 6. Una promesa que hoy nadie puede cumplir

En las Normas de Comunidad quedó escrito:

> *«Nos comprometemos a revisar todo reporte dentro de las 24 horas.»*

**No hay dónde verlos.** Los reportes entran a Firestore con el `read` cerrado a
todo cliente —que está bien, un denunciante que lee reportes ajenos es un canal
de acoso nuevo— pero nadie construyó la vista de revisión.

Eso hay que resolverlo **antes** de publicar esas Normas, no después. No es una
feature que falta: es una afirmación falsa en un documento que estás por
publicar.

---

## 7. El sitio público

Las rutas legales viven bajo **`/es/`** en `gettreino.com` (Next.js con
`[locale]`, repo `treino-app`). Cuatro publicadas, seis faltan.

### El botón de arrepentimiento: re-verificación PENDIENTE, y falta el segundo botón

**Estado: no verificado.** No «cumple» hasta que alguien lo contraste contra el
texto original de la 954/2025.

Lo que sí se sabe: el botón tiene enlace en el pie de la home, texto literal
«Botón de Arrepentimiento», **formulario sin login**, informa el plazo (decía
14 días; el paso a 10 va en `treino-app`, rama
`chore/legal-arrepentimiento-10-dias`, sin desplegar al 2026-09-25) y
menciona el código de identificación. Esos requisitos siguen vigentes bajo la
**Disposición 954/2025** (BO 4/9/2025), así que **no hay motivo para creer que
haya dejado de cumplir por la derogación**.

**Pero eso no es lo mismo que cumplir.** La transcripción literal del art. 1 no se
pudo confirmar contra el Boletín Oficial, y un texto que no se leyó puede traer
condiciones que no están en esta lista. Tratar esto como un gate legal aprobado
sería adelantarse. → [spec-web-legal.md §3.1](./spec-web-legal.md).

> ⚠️ **La verificación original estaba hecha contra una norma derogada.** Decía
> «verificado contra la Resolución 424/2020, punto por punto». El art. 10 de la
> 954/2025 derogó esa resolución y la 316/2018. Los requisitos **conocidos**
> sobrevivieron casi iguales, así que probablemente siga cumpliendo — pero
> «probablemente» no es «verificado», y afirmar «ya cumple» apoyado en una norma
> muerta es exactamente la advertencia falsa de la §11.1 de `AGENTS.md`.
> Corregido el 2026-09-21.

**Lo que la 954/2025 agrega y no teníamos: el «BOTÓN DE BAJA DE SERVICIO»** (su
art. 4). Es un **segundo botón**, distinto del de arrepentimiento y distinto de
`/es/eliminar-cuenta`, con los mismos requisitos de ubicación y acceso. Alcanza al
plan del **entrenador** (cobro directo); la baja del **alumno** la gestionan Apple
y Google. El art. 8 dio 60 días para adecuarse: **exigible desde el 2025-11-04,
o sea que estamos fuera de plazo.**

**La puerta pública se construyó** en `treino-app#15`, mergeado el 2026-09-21:
link en el pie con el texto literal y página sin login, las dos verificadas
contra producción. → [spec-web-legal.md §3.5](./spec-web-legal.md).

> 🚨 **Pero el canal que registra las solicitudes está caído, en los DOS
> botones.** Medido el 2026-09-21: `/api/arrepentimiento` y
> `/api/baja-de-servicio` contestan `{"configured":false}`. La variable
> `ARREPENTIMIENTO_WEBHOOK_URL` nunca se cargó en Vercel, así que toda solicitud
> válida recibe un `503`: no se registra, no se emite código y no sale correo.
>
> No se arregla con código, pero **tampoco alcanza con cargar una variable**: al
> 2026-09-10 el Apps Script que tiene que recibir las solicitudes **no existía**.
> Son dos pasos —crear el destino, después cargar
> `ARREPENTIMIENTO_WEBHOOK_URL`— y saltearse el primero deja la variable
> apuntando a la nada. El endpoint de baja cae a esa misma variable a propósito,
> así que **con una andan los dos**. → [spec-web-legal.md §3.5](./spec-web-legal.md).
>
> Un botón visible con el canal muerto es peor que no tenerlo: la persona se va
> creyendo que hizo el trámite. **Es lo más urgente de este archivo.**

### El problema que ya existe

**Hay dos políticas de privacidad distintas publicadas del mismo producto:**

| | `gettreino.com/es/privacidad` | `app.gettreino.com/legal/privacidad.html` |
|---|---|---|
| Secciones | 7 | 11 |
| Fecha | marzo 2026 | septiembre 2026 |
| Base legal, menores, ubicación | no las menciona | sí |

Y ninguna refleja los documentos nuevos. El desfasaje que el generador vino a
evitar **ya pasó**, cruzando repos, donde ningún CI puede verlo.

### La decisión que quedó sin tomar

**¿Se extiende el generador para que emita también el JSON de next-intl que
consume la landing, o se copian las páginas a mano?**

Copiarlas a mano crea una tercera fuente del mismo texto legal, en otro
repositorio, sin ningún gate de sincronización. Es exactamente el movimiento que
rompió la sincronización las dos veces anteriores.

**Desde el 2026-09-17 el generador está a un solo marcador.** Los once de
revisión legal se cerraron el 16/09, y el del barrido el 17/09 al encenderlo.
Queda **el INPI**, y con presentar la solicitud alcanza.

> ⚠️ **El generador y la landing tienen que salir juntos.** Hoy las dos están
> viejas. Si el generador corre solo, la app pasa a tener el texto nuevo y
> `gettreino.com` se queda con el de marzo: el desfasaje se agranda en vez de
> cerrarse, y la URL que Play Console tiene declarada apunta a la landing.

---

## 8. Las siete preguntas para el abogado

Están en `briefing-revision-legal.pdf`. Resumidas:

1. **Descargo médico** — alguien se lesiona siguiendo una rutina de la app.
   ¿Resiste el texto? ¿Qué forma de aceptación hace falta, y si quien entrena es
   menor?
2. **Relación con los entrenadores** — no pedimos redacción, pedimos el **manual
   de operación**: rige la primacía de la realidad, el contrato pesa poco y la
   conducta pesa todo.
3. ~~**Menores de 9 años con alcance mundial**~~ — **RESUELTA** el 2026-09-16
   subiendo la edad mínima a **13**. COPPA alcanza a los menores de 13, así que
   con ese piso no hace falta mecanismo de consentimiento parental verificable.
   **Queda pendiente el código**, especificado aparte.
4. **Alcance mundial en protección de datos** — qué incorporar sobre la Ley
   25.326.
5. **Retención tras un pedido de supresión** — hoy se conservan el registro de
   pagos, la puntuación de las reseñas y el hilo de chat.
6. **Encuadre del cobro** — validar las dos vías, y sobre todo el tratamiento
   fiscal de cada una.
7. **Publicación a nombre de una persona humana** — si la declaración del Aviso
   Legal alcanza frente a un consumidor.

**La 3 es la que más urge**, porque hay un bloqueante de publicación esperando
su respuesta.

---

## 9. La exposición más alta del producto

Vale decirlo sin vueltas, porque atraviesa varias decisiones:

TREINO permite que **adultos cuyas credenciales la plataforma no verifica**
tengan **mensajería privada** con usuarios que pueden tener **13 años**, y acceso
a sus medidas corporales y a las fotos que suban.

La recomendación técnica había sido edad mínima 18 por este motivo. El titular
fijó primero 9 y el 2026-09-16 la subió a **16**, que es lo que desactiva COPPA y
el art. 8 del RGPD. **La exposición se reduce pero no desaparece:** el vínculo
adulto no verificado ↔ menor de edad sigue existiendo para todo alumno menor de
18, y con el piso en 13 alcanza a una franja más amplia que antes. Lo que la mitiga hoy es el bloqueo, el reporte y la baja del entrenador,
más las obligaciones de la sección 5.bis del contrato del entrenador.

---

## 10. Dónde está cada cosa

| Archivo | Qué es |
|---|---|
| `docs/legal/AUDITORIA-legal-vigente.md` | Los 18 hallazgos, con evidencia de código |
| `docs/legal/BRIEFING-revision-legal.md` | Alcance y las siete preguntas |
| `docs/legal/spec-web-legal.md` | Requisitos del sitio público, autocontenido |
| `docs/legal/*.md` | Los diez documentos |
| `docs/legal/guia-legal-treino.pdf` | Guía de decisiones y trámites |
| `docs/legal/documentos-legales-treino.pdf` | Los diez compilados, pendientes resaltados |
| `docs/legal/briefing-revision-legal.pdf` | El briefing, para mandar al abogado |
| `openspec/changes/moderacion-reporte-y-bloqueo/` | Propuesta, diseño y tareas de moderación |
| `scripts/build_legal_content.py` | Markdown → Dart |
| `scripts/build_legal_docs_pdf.py` | Markdown → PDF de revisión |
| `scripts/build_briefing_pdf.py` | Briefing → PDF |

**Los PDF se regeneran**, no se editan: los tres leen los mismos markdown.

---

## 11. Trampas de este repo, aprendidas a los golpes

Para quien siga:

- **Hay tres guards de ratchet** —color, radios y tipografía— que prohíben
  literales en archivos nuevos. El de tipografía entró el 2026-09-07. Me cazaron
  **dos veces en una sesión**. Usá `AppPalette`, `AppRadius` y `AppTextSize`
  desde el primer renglón.
- **Leer el final del output de `flutter test` engaña.** El contador de fallos es
  acumulado, así que el último test nombrado no es el que falló. Filtrá por
  `[E]`. Me equivoqué dos veces seguidas diagnosticando el mismo CI rojo.
- **Un rebase puede borrar trabajo ajeno sin marcar conflicto.** El chequeo de la
  regla 11.2 de AGENTS.md es obligatorio, y en una de las corridas destapó que
  main había avanzado 164 commits desde el rebase anterior.
- **Los tests de reglas con mocks tapan un `PERMISSION_DENIED`.** El bug del
  `toJson()` era invisible para seis tests verdes. Cruzá el modelo contra las
  reglas reales.
- **Un control negativo vale más que un verde.** Los 5 fallos de la suite de
  reglas se resolvieron corriendo lo mismo contra el `firestore.rules` de main:
  cuatro preexistentes, y el quinto pasaba aislado.
