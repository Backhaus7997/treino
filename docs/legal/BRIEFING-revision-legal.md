# Briefing para la revisión legal

**Cliente:** BACKHAUSTIN S.A.S. — CUIT 30-71929587-4
Molino de Torres 5301, Córdoba Capital, Córdoba (CP 5021), Argentina
Contacto: treino@gettreino.com

**Fecha:** [[completar al enviar]]

---

## Qué es TREINO

Una aplicación móvil de entrenamiento físico, todavía **no publicada**. Tiene
tres partes:

1. **Registro de entrenamiento personal** — rutinas, sesiones, progreso.
2. **Red social** — publicaciones con foto, seguidores, rankings por gimnasio.
3. **Marketplace de entrenadores** — entrenadores personales independientes se
   vinculan con alumnos: chat privado, planes, turnos, y acceso a los datos
   corporales que el alumno comparta.

## Cuatro decisiones del titular que condicionan todo

| # | Decisión |
|---|---|
| 1 | **Edad mínima de cuenta: 9 años** |
| 2 | **Alcance mundial** |
| 3 | **Cobro por pasarela de pago externa**, liquidando a cuenta de la sociedad |
| 4 | **La plataforma NO intermedia** el dinero entre alumno y entrenador |

## Datos que importan para el análisis

- Se recolectan **datos de salud**: peso, más de veinte medidas corporales,
  porcentaje de grasa, dolores reportados **con fotografía**, check-in diario de
  ánimo y dolor, planes de alimentación y tests de rendimiento.
- **TREINO no verifica** títulos, matrículas ni antecedentes de los entrenadores.
- El vínculo alumno-entrenador habilita **mensajería privada**.
- El entrenador puede llevar **notas y archivos privados sobre el alumno** que el
  alumno no ve en su aplicación.
- **Las dos suscripciones ya están implementadas y cobrando**: la del entrenador
  por Mercado Pago en la web, la del atleta por compra integrada.

---

## Qué se pide revisar

Diez documentos, en `documentos-legales-treino.pdf`. **Todos son borradores y
ninguno está publicado.** Los bloques resaltados marcan los puntos abiertos.

### Prioridad alta — no se publican sin dictamen

| Documento | Riesgo |
|---|---|
| **Descargo Médico** | Lesión de un usuario entrenando con la aplicación. Es la única defensa |
| **Términos para Entrenadores** | Relación laboral encubierta, y trabajo con menores |

### Prioridad media

Términos y Condiciones · Política de Privacidad · Términos de Suscripción

### Contexto, no revisión

Normas de Comunidad · Consentimiento de datos de salud · Retención y borrado ·
Aviso Legal

---

## Las seis preguntas concretas

No hace falta una revisión general. Lo que necesitamos dictaminado es esto:

**1. Descargo médico.** Una persona se lesiona siguiendo una rutina de la
aplicación o el plan de un entrenador de la plataforma. ¿El texto resiste? ¿Qué
forma de aceptación hace falta? ¿Y si quien entrena es menor y aceptó su
representante legal?

**2. Relación con los entrenadores.** No pedimos redacción: pedimos el **manual
de operación**. Rige la primacía de la realidad, así que necesitamos saber qué
podemos y qué no podemos hacer para que no se configure dependencia — control,
precios, horarios, evaluación.

**3. Menores de 9 años, alcance mundial.** ¿Qué mecanismo de consentimiento
parental es exigible por jurisdicción? ¿Corresponde restringir por edad el
vínculo con entrenadores y el registro de composición corporal? Es la exposición
más alta del producto: adultos sin credenciales verificadas con canal privado
hacia menores.

**4. Alcance mundial en protección de datos.** La política está escrita sobre la
Ley 25.326. ¿Qué hace falta incorporar? Base legal por finalidad, categorías
especiales, transferencias, representante en la Unión Europea, plazos de
notificación.

**5. Retención tras un pedido de supresión.** Hoy se conservan: el registro de
pagos (respaldo contable), la puntuación de las reseñas (promedio del
entrenador) y el hilo de chat (le pertenece también al otro participante). Los
tres sin nombre, sólo con identificador. ¿Es sostenible?

**6. Encuadre del cobro — validar, no definir.** Se resolvió por dos vías:

| | Entrenador | Atleta |
|---|---|---|
| Contrata en | Coach Hub **web** | Aplicación **móvil** |
| Procesa | Mercado Pago | App Store / Google Play |
| Encuadre invocado | **Guideline 3.1.3(f)** — la app es *companion* gratuita de una herramienta web paga | **Guideline 3.1.1** — sin superficie web no hay exención |

Pedimos validar que el encuadre se sostiene, y en particular **el tratamiento
fiscal de cada vía**: son dos regímenes distintos conviviendo en el mismo
producto, en todos los mercados donde se cobre.

---

## Cómo están hechos estos documentos

No salen de una plantilla. Se escribieron **contra el código y las reglas de
base de datos de la aplicación**, verificando qué recolecta y quién lo ve. Por
eso el inventario de datos es exacto y no genérico.

Eso también produjo una **auditoría de los textos legales que la aplicación
tiene hoy** (`AUDITORIA-legal-vigente.md`), con 18 hallazgos. Puede servir para
entender por qué cada cláusula dice lo que dice.

Los documentos se generan desde una fuente única y se publican en la aplicación
y en el sitio por un proceso automatizado, así que **las correcciones se aplican
en un solo lugar**.

## Qué no está incluido

- **Política de cookies** — espera el inventario de terceros del sitio, que está
  en rediseño.
- **Aviso a madres, padres y responsables** — documento consolidado, que
  probablemente haga falta si la revisión confirma que aplica COPPA.
