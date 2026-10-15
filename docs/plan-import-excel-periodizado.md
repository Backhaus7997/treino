# Import de Excel periodizado (Coach Hub)

Estado: **especificación aprobada** (2026-10-15). Fuente de verdad para
implementar el import; las decisiones de producto de acá son del PO y no se
reinterpretan en el código.

Depende de: #1455 (el matcher no adivina variantes) y #1456 (series por
distancia).

## Qué resuelve

El PF baja una plantilla de Excel desde el Coach Hub, arma el plan en su
formato de siempre (días en bloques, semanas en columnas, superseries en un
renglón) y la sube. La web la convierte en una rutina periodizada que el alumno
ya puede ejecutar: el celular y los dos relojes consumen `weeklySets`,
`activeWeeks` y `supersetGroup` desde antes.

## Plantilla

Una hoja `Programa` (más una hoja `Instrucciones` con ejemplos genéricos de
notación — **nunca** ejercicios cargados).

```
| N° | DÍA 1                                | DESCANSOS | SEMANA 1 | SEMANA 2 | … | SEMANA N |
|    | TROTE + ABDOMINAL ELEVACIÓN PIERNAS  |           | 8'+3x20  | 8'+3x24  |   |          |
| 1  | SENTADILLA + SALTO AL PODIO + 6m VEL |    90     | 3x4+2+6m | 3x5+2+6m |   |          |
| 2  | PRESS DE BANCA INCLINADO             |           | 3x8      | 3x9      |   |          |
|    |                                      |           |          |          |   |          |   ← renglones vacíos: se ignoran
| N° | DÍA 2                                | DESCANSOS |          |          |   |          |
…
```

- **Encabezado de día**: una fila con `DÍA N` (acepta `DIA`, mayúsculas o
  minúsculas) en la columna de ejercicio y `DESCANSOS` en la siguiente. Las
  etiquetas `SEMANA 1…N` están en el encabezado del DÍA 1; los encabezados de
  los demás días pueden no repetirlas — las columnas de semana se fijan con el
  primer encabezado.
- **Hasta 7 días** y **hasta 16 semanas** (el techo actual del producto,
  `athlete_entitlement.dart`). La plantilla descargable trae 7 bloques de **10
  renglones** cada uno y 6 semanas; el parser NO depende de esas cantidades:
  lee cualquier cantidad de renglones entre encabezados y cualquier cantidad de
  columnas SEMANA contiguas (1 a 16).
- **Sólo se acepta esta plantilla.** El formato simple viejo se rechaza con un
  mensaje que pide bajar la plantilla nueva desde el Coach Hub. La descarga
  ofrece sólo la nueva.

## Qué renglones se cargan

- Se carga un renglón **si y sólo si tiene texto en la columna de ejercicio**.
- Renglón sin nombre → se ignora, aunque tenga prescripciones en las semanas.
- Renglón con nombre y sin ninguna prescripción → se carga igual (ejercicio sin
  reps).
- Renglones vacíos pueden aparecer en cualquier lugar del bloque.
- **Sin número (`N°` vacío)** → calentamiento: todas sus series `SetType.warmup`.
- Numeración salteada o repetida → aviso, no error.

## Superseries

- `Ej A + Ej B (+ Ej C …)` en un mismo renglón = superserie: un `RoutineSlot` por
  ejercicio, todos con el mismo `supersetGroup`, en orden.
- Cada componente pasa por el matcher (#1455) por separado.
- El descanso del renglón se aplica después de completar toda la superserie (al
  último slot del grupo; los anteriores van sin descanso entre sí).

## Descanso

- Columna `DESCANSOS`, por renglón.
- `90` = 90 s; `1'` = 60 s; `1'30` o `1'30''` = 90 s; `90''` = 90 s.
- Vacía → **60 s**.
- Inválida → error con fila/columna.

## Celda de semana

Gramática (sin distinguir mayúsculas, espacios ignorados):

```
celda      := átomo ('+' átomo)*
átomo      := [series 'x'] objetivo [calificador]
objetivo   := entero          → reps
            | 'max'           → al fallo (SetType.failure, sin reps)
            | número 'm'      → distancia en metros (distanceMeters, #1456)
            | número "'"      → minutos (durationSeconds = n * 60)
calificador:= 'c/pierna' | 'c/brazo' | 'c/lado'   → se guarda como nota del slot
```

- La cantidad de átomos tiene que ser **igual** a la cantidad de ejercicios del
  renglón; si no, error con fila/columna (`3x4+2` en un renglón de 3 ejercicios).
- Si sólo el primer átomo trae series (`3x4+2+6m`), esas series se propagan a
  todos los componentes.
- Si un átomo posterior trae su propio conteo (`8'+3x20`), lo conserva; un
  tiempo o distancia sin conteo es 1 serie.
- `NxR` → N `SetSpec(reps: R)`; `NxMax` → N `SetSpec(type: failure)`;
  `N'` → 1 `SetSpec(durationSeconds: N*60)` en modo duración;
  `Nm` → `SetSpec(distanceMeters: N)` en modo distancia.
- Fórmula ilegible → error con fila, columna (letra) y el valor recibido.

## Celda de semana vacía en un ejercicio con nombre

**Decisión del PO**: el ejercicio **va igual esa semana, sin reps**, y en la
vista previa del Coach Hub sale **en rojo** ("falta cargar reps") para que el PF
las complete en la app. Es un **aviso, no un bloqueo**: un ejercicio puede ir sin
reps.

Modelo: esa semana lleva 1 `SetSpec` sin reps (`reps: null`), así el slot
existe esa semana (no se usa `activeWeeks` para sacarlo) y el editor muestra la
serie como incompleta.

Consecuencia aceptada: no se puede quitar un ejercicio sólo en una semana desde
el Excel; eso se hace después en el editor.

**Semanas vacías al final.** La plantilla trae 6 columnas SEMANA y nadie las
borra, así que las columnas del FINAL que están vacías en todos los renglones
con nombre de todos los días no cuentan: `numWeeks` = la última SEMANA con al
menos una celda con texto, y para esas semanas no se emite ningún aviso. Una
semana vacía en el MEDIO (1, 2 y 4 cargadas, 3 vacía) no se recorta: sus celdas
siguen la regla de arriba (rojo) y se suma un aviso `emptyWeek` ("SEMANA 3 está
vacía en todo el plan"). Si TODAS las semanas están vacías, `numWeeks` = 1 y los
ejercicios van sin reps (sin error).

## Ejercicios que no matchean

Política de #1455: exacto o alias → se asigna solo; aproximado → sugerencia
confirmable; sin candidato → rojo con "Asignar manualmente". **Ambos bloquean
la asignación** hasta resolverse.

Pendiente de decisión del PO: si una fila sin coincidencia se convierte en
ejercicio propio (al confirmar o automáticamente). Hasta decidirlo, queda como
hoy.

## Mapeo al modelo

- Cada bloque `DÍA N` → `RoutineDay(dayNumber: N)`.
- `Routine.numWeeks` = cantidad de columnas SEMANA, sin contar las vacías del
  final (ver «Semanas vacías al final»).
- `RoutineSlot.weeklySets[w]` = series de la columna SEMANA w+1 (índice 0-based).
- `activeWeeks` = vacío (todas las semanas): con la decisión de arriba, ningún
  slot falta en una semana.
- Campos legacy del slot (`sets`, reps objetivo) = semana 1, como hace el editor.
- `restSeconds` = descanso del renglón (o 60).

## Errores y avisos

El parser junta **todos** los diagnósticos (no corta en el primero), cada uno
con hoja, fila Excel 1-based, columna (letra) y valor recibido.

- **Errores (bloquean la subida)**: no es la plantilla nueva; columnas SEMANA no
  contiguas o duplicadas; más de 16 semanas; más de 7 días o día repetido;
  renglón con nombre fuera de un bloque DÍA; celda ilegible; cantidad de
  ejercicios ≠ cantidad de átomos; descanso inválido; plan sin ningún ejercicio.
- **Avisos**: numeración salteada; ejercicio sin reps en alguna semana (rojo en
  la vista previa); calificador guardado como nota.

## Entregas

- **3a** — plantilla descargable, parser, mapeo a `Routine`; tests unitarios de
  gramática, renglones, superseries, descanso, días/semanas, errores y un
  round-trip plantilla → parser.
- **3b** — vista previa (selector de semana, superseries agrupadas, chips de
  calentamiento/fallo/duración/distancia, rojos y avisos con su celda),
  asignación al alumno y test integrado import → `Routine` que se persiste.
