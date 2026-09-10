# Rutinas: biblioteca del PF y asignación a alumnos

**Estado:** diseño acordado, sin implementar (salvo lo que dice §6).
**Fecha:** 2026-09-10.
**Para:** la sesión que tome este tema. Leé §2 antes que nada — hay una premisa
falsa que hace perder tiempo.

---

## 1. Lo que el PF pidió, en sus palabras

> «Que las rutinas que yo cree sean siempre mías, del PF, y con eso puedo jugar
> e ir asignando, reutilizándolas, en diferentes alumnos que tengan el mismo
> objetivo, pero que siempre le queden al PF para no tener que crear rutinas
> infinitas.»
>
> «Que pueda modificarlas y cuando toca guardar, que le salga un cartel
> diciendo algo como: ¿desea crear una copia con las modificaciones o no?,
> cumpliendo la misma función que al editar una foto en el teléfono: o se te
> guarda con los cambios, o te crea una copia con los cambios manteniendo la
> original en la galería.»
>
> «Si le quiere cambiar la rutina a un alumno, que pueda DESASIGNARLA sin que
> se le borre de su perfil, y ahí asignarle la nueva.»
>
> «Lo mismo, esté asignada a un alumno o no la rutina, poder publicarla para
> todos los usuarios que lo sigan al PF. Queda a criterio del entrenador, pero
> que tenga la opción.»

---

## 2. La premisa falsa: **asignar YA copia**

El PF cree que asignar una rutina se la saca de su biblioteca. **No es así**, y
esto hay que verificarlo antes de diseñar nada:

`lib/features/workout/data/routine_repository.dart:636` —
`assignTemplateToAthlete` hace:

```dart
final assigned = template.copyWith(
  id: '',                                   // documento NUEVO
  source: RoutineSource.trainerAssigned,
  assignedTo: athleteId,
  visibility: RoutineVisibility.private,
);
return createAssigned(assigned);
```

La plantilla original **no se toca**. Se puede asignar la misma plantilla a
veinte alumnos y sigue estando. O sea: *«que siempre le queden al PF» ya
funciona*. Lo que falta es que la pantalla lo diga — hoy nada en la UI lo
comunica, y por eso el PF asume lo contrario.

**Consecuencia para el diseño:** no hay que construir un modelo de biblioteca.
Ya existe. Lo que hay que construir es lo de §4.

---

## 3. El modelo de datos, y por qué NO se puede «desasignar» mutando

### 3.1 Los tres tipos de rutina

`lib/features/workout/domain/routine_source.dart`

| `source` | `assignedTo` | quién es el dueño | qué es |
|---|---|---|---|
| `system` | — | la app | catálogo del sistema |
| `trainer-template` | **`null`** | el PF (`assignedBy`) | plantilla reutilizable de la biblioteca |
| `trainer-assigned` | uid del alumno | el PF (`assignedBy`) | la copia que ese alumno entrena |

### 3.2 `assignedTo` y `source` son INMUTABLES, por regla de servidor

`firestore.rules`, verificado:

```
# línea 653-654 — UPDATE path 3: el PF edita un plan asignado
&& request.resource.data.assignedTo == resource.data.assignedTo
&& request.resource.data.source     == resource.data.source

# línea 718-719 — UPDATE path 4: el PF edita una plantilla
&& request.resource.data.assignedTo == null
&& request.resource.data.source     == resource.data.source
```

No hay ningún `allow update` que permita cambiar `assignedTo` ni `source`
después del create. Los cinco paths están en las líneas 531, 540, 628, 693 y
757 de `firestore.rules`.

**Por lo tanto: convertir una rutina asignada de vuelta en plantilla es
rechazado por el servidor.** No es una limitación del cliente ni algo que se
arregle con un método nuevo en el repo. Si alguien lo intenta, el write falla y
el PF ve un error que no puede resolver.

### 3.3 Por qué la regla está bien y NO hay que aflojarla

`lib/features/workout/domain/session.dart:16` — `Session` lleva
`required String routineId`. Las sesiones que el alumno ya entrenó apuntan a
ESE documento.

Es el mismo motivo por el que el PR #1064 hizo que terminar un vínculo
**archive** las rutinas del alumno en vez de borrarlas (ADR-USR-04: «el
documento se conserva para mantener referencias históricas de sesiones»).
Mutar `assignedTo` a `null` dejaría las sesiones del alumno colgando de un
documento que pasó a ser una plantilla del PF.

> ⚠️ **Si la próxima sesión piensa en tocar `firestore.rules` para permitir
> esto: no.** La regla protege datos del alumno. El resultado que el PF quiere
> se consigue sin tocarla — ver §4.1.

---

## 4. Qué hay que hacer, en orden

### 4.1 Desasignar (lo que el PF llama así) — **cambio de UI, no de modelo**

**El resultado que el PF quiere ya se puede:** archivar la copia del alumno. La
copia sale de la lista del alumno y la plantilla del PF queda intacta. Ya está
implementado (`RoutineActionsNotifier.archive`).

Lo que falta es **cómo se lee**:

- Hoy el menú ⋮ de una rutina asignada dice «Archivar». Desde la sección
  Rutinas eso no se lee como «sacársela a este alumno».
- Sobre una rutina `trainer-assigned`, el ítem debería decir algo como
  **«Sacársela a {nombre}»**, y el diálogo aclarar que la plantilla del PF no
  se toca y que los entrenamientos que el alumno ya hizo se conservan.
- Sobre una `trainer-template`, «Archivar» sigue siendo la palabra correcta.

**Es copy + gateo. Cero cambios de esquema, cero de reglas.**

### 4.2 «Guardar» vs «Guardar como copia» al editar — **lo más valioso, y no existe**

La metáfora de la foto. Al guardar cambios en el editor
(`routine_editor_web_screen.dart`), ofrecer:

- **Guardar** → pisa el documento actual (`updateTemplate` / `updateAssigned`,
  ya existen: repo líneas 285 y 232).
- **Guardar como copia** → crea un documento nuevo con los cambios y deja el
  original como estaba (`createTemplate`, repo línea 553).

Encaja con el modelo actual sin tocar reglas ni esquema.

**Decisiones que hay que tomar antes de codear:**

1. ¿El cartel sale **siempre** o sólo si hubo cambios? (Si sale siempre,
   molesta; el editor ya tiene `_isDirty`.)
2. Editando una rutina **asignada**, ¿la copia nace como plantilla
   (`trainer-template`, `assignedTo: null`) o como otra asignada al mismo
   alumno? La primera es la que sirve al caso «esto me quedó bueno, lo quiero
   para reusar».
3. ¿Qué nombre lleva la copia? («Fuerza 4x (copia)» es lo obvio; conviene que
   el diálogo lo deje editar.)
4. El límite del plan free existe y hay que respetarlo: ver
   `freeMaxRoutineDays()` / `freeMaxRoutineWeeks()` en `firestore.rules` y el
   paywall de #1082. Una copia es una rutina nueva y cuenta.

### 4.3 Publicar esté asignada o no

`firestore.rules:757` — UPDATE path 5 restringe el flip de `visibility` a:

```
&& request.auth.uid == resource.data.assignedBy
&& resource.data.source == 'trainer-template'
&& affectedKeys() == ['visibility'].toSet()
```

O sea: **sólo plantillas**. Publicar la copia de un alumno lo rechaza el
servidor — y con razón, esa copia lleva su nombre y su historial.

El PF igual quiere el ítem disponible en cualquier rutina. La forma correcta:

- Si es `trainer-template` → flip directo (**ya implementado**, ver §6).
- Si es `trainer-assigned` → ofrecer **«Publicar como plantilla»**: crear un
  `trainer-template` a partir de esa copia (`createTemplate`) y publicar ESE.
  La rutina del alumno no se toca.

**Decisión a tomar:** eso genera un documento por publicación. Hay que decidir
si el PF lo ve como una plantilla más en su biblioteca (probablemente sí, y
está bien) y qué nombre lleva.

### 4.4 Ordenar la biblioteca — **prerequisito de 4.2**

`routine_repository.dart:483` — `listAuthoredBy` hace un solo
`where('assignedBy', isEqualTo: trainerId)`. Devuelve **plantillas Y todas las
copias asignadas**, mezcladas.

La sección Rutinas las muestra juntas, con filtros
(`rutinas_screen.dart:100`: `todas / asignadas / plantillas / publicas /
archivadas`). Con 20 alumnos y 5 rutinas cada uno, la lista tiene 100 tarjetas
de las cuales 5 son «las tuyas».

**Si se implementa 4.2 antes que esto, cada copia guardada empeora el
desorden.** Conviene separar «Mis rutinas» (plantillas) de «Lo que está
entrenando cada alumno» (asignadas) antes de facilitar la creación de copias.

---

## 5. Orden recomendado

1. **4.1** — copy + gateo. Chico, y desactiva el miedo del PF de una.
2. **4.4** — ordenar la biblioteca. Sin esto, lo que sigue ensucia.
3. **4.2** — guardar / guardar copia. Lo que más suma.
4. **4.3** — publicar desde una asignada.

---

## 6. Lo que YA está hecho (no rehacer)

Rama `feat/coach-hub-rutinas-asignar-publicar`, sobre `main`:

- `RoutineActionsNotifier.assignTemplate(...)` — asigna una plantilla a un
  alumno e invalida los dos listados (la grilla de la sección y el par
  trainer/alumno de la ficha).
- `RoutineActionsNotifier.setPublicada(...)` — publica/despublica una
  plantilla.
- El menú ⋮ de `routine_card_grid.dart` ofrece **«Asignar a un alumno»** y
  **«Publicar en la comunidad» / «Despublicar»**, gateados: sólo sobre
  `trainer-template` no archivadas.
- El aviso de asignar dice explícitamente que **se asignó una copia y la
  plantilla queda**. Esa frase es la que ataca la premisa falsa de §2.
- El selector de alumno se mudó de `sections/pagos/widgets/` al kit como
  `pickAthlete` (dos secciones importándose entre sí es peor que compartirlo).
- Tests: 4 de gateo del menú + 5 del provider, incluido que despublicar llame a
  `unpublishTemplate` y **no** a `publishTemplate` — el peor fallo posible acá
  es que «Despublicar» publique.

---

## 7. Trampas del repo que aplican a este tema

- **`assignedTo` y `source` son inmutables.** Ya dicho, pero es la que más
  tiempo hace perder. Ver §3.2.
- **Un ítem de menú que las reglas van a rechazar es peor que no tenerlo.** El
  PF lo aprieta, ve un error y no aprende por qué. Gatear siempre.
- **Invalidar los DOS listados** después de cualquier mutación:
  `routinesAuthoredByProvider(trainerId)` (la sección) y
  `assignedRoutinesByTrainerProvider((trainerId, athleteId))` (la ficha del
  alumno). Olvidar uno no falla ni compila mal: la card se queda en pantalla
  hasta recargar. Es el fallo silencioso que AGENTS.md §11.1 prohíbe. El
  dartdoc de `archive` en `routine_actions_provider.dart` lo explica largo.
- **El plan free tiene tope de días y semanas por rutina.** Cualquier flujo que
  cree rutinas nuevas (una copia lo es) tiene que contemplarlo.
- **El gate visual corre sólo en Linux CI.** Si la UI cambia, los goldens se
  regeneran con un commit vacío `[regen-goldens]` y hay que aprobar los runs
  que quedan en `action_required`. Ver `docs/visual-gate.md`.
