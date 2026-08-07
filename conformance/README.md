# Fixtures de conformidad Dart ↔ Swift

Escenarios en JSON que **ambas** implementaciones de TREINO deben resolver
igual: la de Dart (teléfono) y la de Swift (reloj, change
`watch-standalone-client`).

## Por qué existen

El cliente watchOS no puede usar el SDK de Firestore — Firebase en watchOS es
community-supported y Firestore ni siquiera figura entre sus productos
soportados. El reloj habla la REST API de Firestore por HTTP, lo que obliga a
**reimplementar en Swift la lógica de negocio que hoy vive en Dart**.

Eso crea el riesgo estructural del change: las mismas reglas escritas dos
veces **van a divergir**. No es una posibilidad, es cuestión de cuándo. Y
cuando pase, el historial de entrenamiento del usuario se corrompe **en
silencio** — nadie se entera hasta que los números no cierran.

Estos fixtures son la única red contra eso. Cada regla portada tiene su
archivo; las dos implementaciones lo leen y CI se pone en rojo apenas una
cambia y la otra no.

## Regla de oro

**El fixture es el contrato, no la implementación.** Si Dart y Swift
discrepan, el fixture decide quién está mal. Si el fixture está mal, se corrige
el fixture **primero** y recién después las dos implementaciones — nunca al
revés, o se pierde la propiedad que hace útil todo esto.

Corolario: no agregues un caso copiando lo que la implementación devuelve hoy.
Escribí primero qué DEBERÍA devolver y por qué. Un fixture que solo confirma el
código existente no protege de nada.

## Formato

```jsonc
{
  "rule": "plan-advance",
  "source_of_truth": "lib/features/workout/domain/plan_advance.dart",
  "description": "...",
  "inputs": { "campo": "qué significa y qué rango admite" },
  "cases": [
    {
      "name": "descripción corta del escenario",
      "why": "opcional — por qué este caso importa, sobre todo si el resultado sorprende",
      "given": { },
      "expect": { }
    }
  ]
}
```

El campo `why` no es decorativo: los casos raros (datos corruptos, valores
fuera de rango) son justo los que alguien va a querer "arreglar" sin entender.

## Archivos

| Archivo | Regla | Implementación Dart | Implementación Swift |
|---|---|---|---|
| `plan_advance.json` | Qué día y semana tocan según la última sesión finalizada | `lib/features/workout/domain/plan_advance.dart` | `ios/TreinoWatch Watch App/PlanAdvance.swift` |
| `routine_selection.json` | Cuál rutina es la activa del atleta | `lib/features/workout/domain/routine_selection.dart` | `ios/TreinoWatch Watch App/RoutineSelection.swift` |

## Quién los corre

Los **dos** lados, y los dos en CI. Ahí está el valor: con uno solo, esto sería
una descripción del comportamiento actual, no una red.

| Lado | Cómo | Dónde |
|---|---|---|
| Dart | `flutter test` | job *Analyze & Test* |
| Swift | `bash conformance/run_swift.sh` | job *Conformance (Swift)* |

El corredor Swift **compila el archivo real del reloj**
(`ios/TreinoWatch Watch App/PlanAdvance.swift`), no una copia. Si alguien lo
cambia sin tocar el contrato, se pone rojo — que es todo el punto. Corre en
ubuntu porque el código bajo prueba solo importa Foundation, disponible en el
Swift de Linux; un runner macOS costaría diez veces más sin aportar nada.

### Verificado que detecta divergencia

No alcanza con que pase. Se rompió a propósito cada implementación y se
comprobó que el corredor del lado correspondiente se pone rojo nombrando los
casos afectados, con esperado vs obtenido. Al romper el `>=` del rollover, los
dos corredores señalaron **los mismos 2 casos de 12** — misma regla, mismo
contrato, mismos modos de falla.

Si agregás una regla nueva a los fixtures, hacé lo mismo: rompela a propósito y
confirmá que salta. Un fixture que nunca se vio fallar no es una red.
