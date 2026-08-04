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

| Archivo | Regla | Implementación Dart |
|---|---|---|
| `plan_advance.json` | Qué día y semana tocan según la última sesión finalizada | `lib/features/workout/domain/plan_advance.dart` |

## Quién los corre

- **Dart**: `test/conformance/plan_advance_conformance_test.dart`, dentro de
  `flutter test`.
- **Swift**: pendiente — se suma cuando el target watchOS tenga lógica que
  verificar (fase F2 de `watch-standalone-client`).

Mientras exista un solo lado corriéndolos, los fixtures todavía **no** protegen
de la divergencia: solo fijan el contrato para cuando llegue el segundo. Esa
brecha es conocida y está anotada en
`openspec/changes/watch-standalone-client/state.yaml`.
