# Rutinas: biblioteca del PF y asignación a alumnos

**Estado:** §4.1, §4.2 y §4.4 implementados y mergeados. Falta **§4.3**.
**Fecha:** 2026-09-10 (reescrito; la versión anterior tenía dos premisas falsas).
**Para:** la sesión que tome §4.3, o cualquiera que toque rutinas del PF.

> **Los números de línea de este doc se desactualizan.** Los de la versión
> anterior estaban corridos ~40 líneas y hacían desconfiar del doc entero.
> Tratalos como una pista, no como una dirección: verificá con `rg` antes de
> creerles.

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

## 2. La premisa falsa del PF: **asignar YA copia**

El PF creía que asignar una rutina se la sacaba de su biblioteca. No es así:
`assignTemplateToAthlete` (`routine_repository.dart:656`) hace `copyWith(id: '')`
y crea un documento NUEVO. La plantilla no se toca. Se puede asignar la misma
plantilla a veinte alumnos y sigue estando.

Su dartdoc lo dice explícito: *«The template itself is left untouched so it can
be reused for other athletes»*.

**Esto sigue siendo cierto y ahora la UI lo dice**: el aviso de asignar
(#1091) declara que se asignó una COPIA y que la plantilla queda.

---

## 3. El modelo de datos

### 3.1 Los tres tipos de rutina

`lib/features/workout/domain/routine_source.dart`

| `source` | `assignedTo` | dueño | qué es |
|---|---|---|---|
| `system` | — | la app | catálogo del sistema |
| `trainer-template` | **`null`** | el PF (`assignedBy`) | plantilla reutilizable |
| `trainer-assigned` | uid del alumno | el PF (`assignedBy`) | la copia que ese alumno entrena |

### 3.2 `assignedTo` y `source` son INMUTABLES, por regla de servidor

Ningún `allow update` de `/routines` los deja cambiar después del create.
**Convertir una rutina asignada de vuelta en plantilla lo rechaza el servidor.**
No es una limitación del cliente ni algo que se arregle con un método nuevo.

### 3.3 Por qué la regla está bien y NO hay que aflojarla

`Session` lleva `required String routineId`. Las sesiones que el alumno ya
entrenó apuntan a ESE documento. Es el mismo motivo por el que el PR #1064 hizo
que terminar un vínculo **archive** las rutinas en vez de borrarlas (ADR-USR-04).
Mutar `assignedTo` a `null` dejaría las sesiones del alumno colgando de un
documento que pasó a ser una plantilla del PF.

> ⚠️ **Si pensás en tocar `firestore.rules` para permitir eso: no.** El
> resultado que el PF quiere se consigue archivando la copia — ver §4.1.

### 3.4 Los seis paths de UPDATE

Están en el bloque `match /routines/{routineId}` (`firestore.rules:324`):

| path | quién | qué puede cambiar |
|---|---|---|
| 1 | el atleta dueño (`user-created`) | sólo `status` (archivar / restaurar) |
| 2 | el atleta dueño | contenido |
| 3 | el PF (`trainer-assigned`) | contenido: `name split level days numWeeks summary` |
| 4 | el PF (`trainer-template`) | idem + `goals` |
| 5 | el PF (`trainer-template`) | sólo `visibility` (publicar / despublicar) |
| **6** | **el PF (`trainer-*`)** | **sólo `status` (archivar / recuperar)** |

El path 6 es de #1092 y se agregó porque **faltaba** — ver §4.1.

---

## 4. El plan

### 4.1 «Desasignar» — HECHO (#1092)

**La versión anterior de este doc decía que esto era «copy + gateo, cero
cambios de reglas» porque `RoutineActionsNotifier.archive` ya existía. Era
falso: el método existía y el servidor lo denegaba.**

`status` no estaba en el `affectedKeys().hasOnly([...])` de ningún path del PF
—los 3 y 4 son de CONTENIDO— y el único que sí flipea `status` (path 1) exige
`source == 'user-created'`. Los cinco paths denegaban. Desde `fdce15c7`
(2026-07-17), en las dos pantallas de rutinas del Hub.

No fallaba ruidosamente: `archive()` atrapa el `permission-denied` y devuelve
`false`, así que el PF veía **«No se pudo. Probá de nuevo.»** cada vez. Dos
meses.

Nada en Dart lo veía. El repo compila igual, y los seis widget tests de
archivar de `athlete_routines_screen_test.dart` pasaban en verde: mockean el
repositorio, así que prueban que el cliente LLAMA, nunca que el servidor acepte.

Lo entregado:

- **UPDATE path 6** (`firestore.rules:820`), angosto: el dueño flipea SÓLO
  `status` entre `active` y `archived` sobre sus `trainer-*`.
- `RoutineRepository.unarchive` (`routine_repository.dart:355`). Sin el camino
  de vuelta, archivar es un borrado con otro nombre y todo diálogo que prometa
  recuperar miente — que es lo que decía el de la card mientras no existía.
- El ⋮ sobre un plan asignado dice **«Sacársela a {nombre}»**
  (`routine_card_grid.dart:364`); sobre una plantilla sigue diciendo
  «Archivar». Sobre una archivada aparece **«Recuperar»**.
- 12 tests de reglas (`scripts/rules_test/trainer-routine-status.test.js`).

**El diálogo NO promete que la plantilla del PF queda intacta**, que era lo que
pedía el diseño original. Sería verdad sólo si ese plan hubiera salido de una
plantilla, y no hay forma de saberlo: `createAssigned` se llama desde tres
pantallas que arman el plan a mano y la rutina no guarda de qué documento se
copió. Dice las tres cosas que sí son ciertas siempre: el alumno deja de verla,
sus entrenamientos se conservan, y queda en Archivadas.

### 4.2 Guardar / guardar como copia — HECHO (#1097)

El cartel sale al guardar una rutina que **ya existe** y **tiene cambios**
(`_preguntarComoGuardar`, `routine_editor_web_screen.dart:2493`). Las dos
condiciones importan: uno que sale siempre enseña a apretar el primer botón sin
leer, y ahí se pierde el peso de todas las confirmaciones de la pantalla.

Las cuatro decisiones que este doc dejaba abiertas, resueltas:

1. **¿Siempre?** No: sólo editando y sólo con `_isDirty`.
2. **¿La copia de un plan asignado es plantilla o plan?** **Plantilla.** Es el
   caso que el PF describió y el único que construye biblioteca; una copia
   asignada al mismo alumno le suma una tarjeta a esa persona y no le sirve a
   nadie más.
3. **¿Qué nombre?** «X (copia)», automático. La metáfora de editar una foto no
   tiene paso de nombre. Un campo en el diálogo queda ignorado por el botón
   «Guardar», y un segundo diálogo agrega fricción justo cuando el PF quiere
   terminar.
4. **El tope del plan free** no era una decisión sino una restricción: la copia
   pasa por el mismo `try/catch` y el mismo `_onWriteDenied`.

La rama de la copia **no llama a ningún `update`**. Ésa es toda la promesa de
«mantener la original en la galería», y hay test con `verifyNever` que la fija.

### 4.3 Publicar esté asignada o no — **PENDIENTE, lo único que queda**

`firestore.rules` restringe el flip de `visibility` a `trainer-template` del
dueño (path 5). Publicar la copia de un alumno lo rechaza el servidor — y con
razón, esa copia lleva su nombre y su historial.

La forma correcta:

- `trainer-template` → flip directo (**ya implementado**, #1091).
- `trainer-assigned` → ofrecer **«Publicar como plantilla»**: `createTemplate` a
  partir de esa copia y publicar ESE. La rutina del alumno no se toca.

Con §4.2 puesto, la mitad de esto ya existe: «Guardar como copia» desde el
editor de un plan crea exactamente esa plantilla. Falta el atajo desde el ⋮ y el
publicar.

**Decisión sin tomar, y no es menor: publicar expone el NOMBRE al catálogo
público.** Un plan asignado suele llamarse «Plan de Sofía». Publicarlo tal cual
filtra el nombre de una clienta a la comunidad. Acá **sí** hace falta que el PF
lo renombre antes de publicar — al revés que en §4.2, donde la copia es privada
y el nombre va automático. La diferencia no es de gusto: una es privada y la
otra es pública e irreversible en la práctica (junta valoraciones).

⚠️ **§4.3 toca `routine_card_grid.dart` y `routine_actions_provider.dart`**, los
mismos métodos que #1092. Si hay otro PR abierto sobre esos archivos, esperalo:
apilar es una trampa acá (el squash del padre cierra al hijo y no se puede
reabrir).

### 4.4 Ordenar la biblioteca — HECHO (#1093 + #1096)

**La versión anterior de este doc decía que había que separar «Mis rutinas» de
«Lo que entrena cada alumno» dentro de la sección Rutinas. Le faltaba el dato
que cambiaba el problema: esa separación YA EXISTÍA como sección, y el problema
real era la duplicación.**

Las plantillas del PF se listaban en DOS lugares del Hub, y no eran
equivalentes:

| | `Biblioteca › Plantillas` | `Rutinas` |
|---|---|---|
| qué mostraba | sólo plantillas | plantillas **+** planes asignados |
| acciones | tap → diálogo de detalle | ⋮ completo |
| publicar | «se hace desde el editor» | desde el menú |

O sea: el lado bonito era el inerte. Duplicar una lista es tolerable;
duplicarla con capacidades distintas es cómo se desincronizan las cosas.

Lo entregado:

- **#1093**: Rutinas se parte en «MIS PLANTILLAS» y «LO QUE ENTRENA CADA
  ALUMNO», las asignadas agrupadas bajo el nombre de su alumno. Los chips pasan
  de cinco a tres (`Vigentes · Públicas · Archivadas`): «Plantillas» y
  «Asignadas» dejaron de ser filtros para ser los bloques.
- **#1096**: se retira la sub-tab Plantillas de Biblioteca, que queda sólo para
  Ejercicios, y se borra el cluster huérfano (`templates_tab`,
  `template_grid_card`, `template_detail_dialog`, `template_format` + 2 tests).

`trainerTemplatesStreamProvider` sigue vivo: lo usa la pestaña Plantillas del PF
en **mobile** (`trainer_workout_view.dart`). Fue una decisión sobre las
secciones del Hub **web**.

---

## 5. Lo que queda

Sólo **§4.3**. Con su decisión de nombre sin tomar.

Aparte, dos cosas que quedaron señaladas y no hechas:

- `athlete_routines_screen.dart` no ofrece «Recuperar». Su copy es honesto —
  promete VER la rutina en Archivadas, no recuperarla— así que no miente, pero
  la acción existe y esa pantalla no la expone.
- La sección `Biblioteca` ahora es sólo ejercicios y sigue llamándose
  «Biblioteca». Si «Ejercicios» describe mejor lo que quedó, es un PR de naming
  aparte (AGENTS.md §1 es estricto con eso).

---

## 6. Trampas del repo que aplican a este tema

Ordenadas por cuánto tiempo hacen perder.

1. **Un repo mockeado tapa un `permission-denied`.** Los widget tests
   verifican que el cliente LLAMA al método, nunca que el servidor lo acepte.
   Un botón puede estar roto dos meses con la suite en verde y `dart analyze`
   limpio. **Toda escritura nueva a Firestore necesita un test en
   `scripts/rules_test/`.**

2. **La suite de reglas con `firebase-tools@13` da 4 rojos falsos.** Java 17 no
   le alcanza a la 15, así que la salida obvia es `npx -y firebase-tools@13` — y
   con esa CLI fallan siempre `SCENARIO-PERIOD-050`, `-054`,
   `WPRES-RULES-01` y el de paywall/rutina inexistente. En CI (que usa la 15)
   pasan. El JDK 21 ya está instalado en esta máquina; el comando correcto y el
   control negativo que aísla el efecto están en la cabecera de
   `scripts/test_rules.sh` (#1095), no en `docs/`.

3. **`assignedTo` y `source` son inmutables.** §3.2. La que más tiempo hace
   perder si no se lee.

4. **Un ítem de menú que las reglas van a rechazar es peor que no tenerlo.** El
   PF lo aprieta, ve un error y no aprende por qué. Gatear siempre — y probar
   el gateo contra el emulador, no contra un mock.

5. **Invalidar TODOS los listados después de cualquier mutación.** Son tres
   lectores: `routinesAuthoredByProvider(trainerId)` (la sección),
   `assignedRoutinesByTrainerProvider((trainerId, athleteId))` (la ficha del
   alumno) y las cachés single-doc vía `invalidateRoutineById`. Olvidar uno no
   falla ni compila mal: la card se queda en pantalla hasta recargar.
   **El editor web se olvidaba del primero para TODOS sus caminos de
   escritura** — arreglado en #1097. Es `autoDispose` y al editor se llega por
   `context.push`, así que la ruta de abajo sigue montada y el provider nunca se
   dispone.

6. **Que la escritura se describa a sí misma, no a la pantalla.** Guardar como
   copia desde el editor de un plan escribe una PLANTILLA, pero
   `widget.isTemplate` sigue en `false` y `widget.athleteId` no es `null`.
   Cuatro lugares miraban la pantalla y mentían: el `athleteId` y el `source` de
   analytics, la `operation`, y el copy de la denegación. Si agregás una rama de
   escritura, revisá qué más deriva del modo de la pantalla.

7. **El plan free tiene tope de días y semanas por rutina.** Cualquier flujo
   que cree rutinas nuevas (una copia lo es) tiene que contemplarlo.

8. **El gate visual corre sólo en Linux CI.** Si la UI cambia, los goldens se
   regeneran con un commit vacío `[regen-goldens]` y hay que aprobar los runs
   que quedan en `action_required`. Ver `docs/visual-gate.md`.

9. **Un `SnackBar` sin drenar rompe el test SIGUIENTE.** Deja un `Timer` vivo.
   El síntoma es un test que falla en suite y pasa en aislamiento: se arregla
   con `await tester.pump(const Duration(seconds: 6))` al final del que lo
   muestra.

10. **`TreinoSectionHeader` uppercasea el título.** `find.text('Biblioteca')`
    falla; es `'BIBLIOTECA'`.
