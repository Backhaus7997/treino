# Plan — el gate del paywall en el reloj de Apple (watchOS)

> **Es lo único que falta para poder ENCENDER el paywall del alumno.**
> Mientras esto no esté, no se toca `kAthletePaywallEnabled` ni la CF que
> escribe `athletePaywallEnforced`. Ver §5.

Contexto: [paywall-alumno-suelto.md](./paywall-alumno-suelto.md) §4.1.1 — seguir
una plantilla de nivel principiante es gratis; las de intermedio y avanzado son
del plan pago.

Este documento lo escribió una sesión que trabajaba desde Windows y **no podía
compilar Swift**. Todo lo que dice del código está verificado por lectura y
citado con `archivo:línea`; nada está verificado por ejecución. Donde hay una
suposición, está marcada.

---

## 1. Dónde estamos

| pieza | estado | dónde |
|---|---|---|
| Topes de forma (días / semanas) | ✅ | #1082 |
| Catálogo — UI del teléfono | ✅ | #1066 |
| Catálogo — regla server-side sobre `sessions` | ✅ | #1087 |
| Catálogo — gate del reloj **Wear OS** | ✅ | #1087 |
| **Catálogo — gate del reloj de Apple** | ❌ | **este documento** |

La regla del #1087 **nace inerte**: `athletePaywallEnforced` ausente ⇒ no se
aplica, y hoy la CF lo escribe en `false` en todos lados. Por eso se pudo
mergear sin el watchOS. Eso deja de valer el día que el flag se encienda.

---

## 2. El inventario, verificado

Tres cosas faltan, y son independientes entre sí.

### 2.1 `RoutineSummary` no transporta `isPremium`

[`RoutineCatalog.swift:36-42`](../ios/TreinoWatch%20Watch%20App/RoutineCatalog.swift) —
la estructura tiene `id`, `name`, `numWeeks`, `dayCount`, `origin`. Nada más.

Se construye en `summary(_:origin:)`
([`RoutineCatalog.swift:191`](../ios/TreinoWatch%20Watch%20App/RoutineCatalog.swift)),
que lee el doc crudo de Firestore. El campo **está en el documento** —
`docs/video-catalog-audit/improved-templates.json` lo trae en las 7 plantillas y
`scripts/seed_templates.js` las escribe con `{ ...t }` — así que es cuestión de
leerlo, no de denormalizarlo.

`FirestoreREST` ya tiene el decodificador: `FS.bool(_:)`
([`FirestoreREST.swift:235`](../ios/TreinoWatch%20Watch%20App/FirestoreREST.swift)).

### 2.2 El reloj no tiene fuente de entitlement

No hay nada en `TreinoWatch Watch App/` que lea `athleteSubscription`, ni
`trainer_links`, ni `athletePaywallEnforced`.

Lo que **sí** tiene es el camino: `RoutineCatalog.setActiveRoutine` ya escribe
`users/{uid}` por REST
([`RoutineCatalog.swift:184`](../ios/TreinoWatch%20Watch%20App/RoutineCatalog.swift)),
y `FirestoreREST.document(path:)`
([`FirestoreREST.swift:43`](../ios/TreinoWatch%20Watch%20App/FirestoreREST.swift))
lee un documento por path conocido.

**Leer `users/{uid}.athletePaywallEnforced` es la opción correcta**, y no es la
misma decisión que tomó el teléfono. El teléfono cruza dos fuentes
(`athleteSubscription` **OR** vínculo con un PF activo) porque puede: tiene el
SDK y los providers. El reloj no puede resolver `trainer_links` — ids
autogenerados, y por REST eso es una query más y otra ronda de red en el camino
crítico de "tocar Empezar". `athletePaywallEnforced` es exactamente la
conclusión ya cruzada de esas dos fuentes, escrita por la CF, y es el mismo
campo que lee `firestore.rules`. Un solo `get`, y el reloj coincide con el
servidor por construcción.

> **Trampa que esto evita:** si el reloj resolviera el entitlement por su cuenta
> y se equivocara para el otro lado, le cortaría el entrenamiento a alguien que
> paga. Leer la misma conclusión que la regla hace que el gate del reloj no
> pueda ser más estricto que el servidor.

### 2.3 `syncError` no lo renderiza ninguna vista

Y **lo confesa su propio código**:
[`WorkoutView.swift:126-132`](../ios/TreinoWatch%20Watch%20App/WorkoutView.swift)
dice, sobre el fallo de cierre, *"el del historial se guardaba en `syncError`,
que no lo renderizaba ninguna vista"*. La solución de aquel momento fue agregar
`closeFailure` y su banner
([`WorkoutView.swift:377`](../ios/TreinoWatch%20Watch%20App/WorkoutView.swift));
`syncError` quedó como estaba.

`WorkoutCoordinator` lo asigna 7 veces: cuatro con un error de verdad (`:243`,
`:270`, `:466`, `:786`) y tres limpiándolo a `nil`. **Ninguna vista lo lee.**

**Es el mismo agujero que el #1087 cerró del lado Wear**, con otro mecanismo. En
Wear el deny moría en un `developer.log`; acá muere en una propiedad que nadie
observa. El síntoma para el atleta es idéntico: entrena una hora contra una
sesión que el servidor rechazó, y se entera cuando abre el teléfono.

---

## 3. El orden de trabajo

**El fixture va PRIMERO.** No es preferencia: es la regla de oro de
[`conformance/README.md`](../conformance/README.md) — *"Si el fixture está mal,
se corrige el fixture primero y recién después las dos implementaciones — nunca
al revés, o se pierde la propiedad que hace útil todo esto."*

Y hay un motivo extra para respetarla acá: **el job `Conformance (Swift)` corre
en `ubuntu-latest`**, no en macOS
([`ci.yml:283`](../.github/workflows/ci.yml)). O sea que la lógica pura de Swift
se compila y se ejercita en CI de verdad. Un fixture no es documentación: es la
única parte de este trabajo que da verificación real sin una Mac.

### Paso 1 — el fixture y la función pura ✅ HECHO

> Quedan hechos: `conformance/catalog_gate.json` (8 casos), su test Dart, y la
> extracción de `catalogGateBlocks` a
> [`lib/features/paywall/domain/catalog_gate.dart`](../lib/features/paywall/domain/catalog_gate.dart).
> **El contrato ya existe y el lado Dart lo cumple.** Lo que sigue es escribir
> la mitad Swift y cablearla en `conformance/swift/main.swift`.
>
> Se agregó además `test/conformance/fixture_coverage_test.dart`, un guard que
> falla si un fixture no está invocado en el runner Swift — porque ese runner
> no descubre nada solo y un `.json` olvidado deja el contrato unilateral **en
> silencio**. `catalog_gate.json` está declarado ahí como deuda consciente, con
> su motivo.
>
> **Sacarlo de esa allowlist es parte de terminar este trabajo.** Cuando lo
> saques, el guard empieza a exigir el runner Swift por su cuenta.

<details>
<summary>El contenido del fixture, para referencia (ya está en el repo)</summary>

La regla portada es: **¿este alumno puede entrenar esta plantilla?**

```jsonc
{
  "rule": "catalog-gate",
  "source_of_truth": "lib/features/paywall/application/athlete_entitlement_provider.dart",
  "description": "Si el candado del catalogo pago frena entrenar una plantilla. Contrato compartido entre Dart (telefono y Wear) y Swift (watchOS). Si divergen, el mismo alumno entrena una plantilla en un reloj y no en el otro.",
  "inputs": {
    "paywallEnabled": "El interruptor maestro (kAthletePaywallEnabled). false = nada se gatea.",
    "paywallEnforced": "users/{uid}.athletePaywallEnforced, la conclusion que escribe la CF. Ausente = null = no se aplica.",
    "isPremium": "El flag de la plantilla. Ausente = null = gratis."
  },
  "cases": [
    { "name": "flag apagado: ni la paga se frena",
      "given": { "paywallEnabled": false, "paywallEnforced": true, "isPremium": true },
      "expect": { "blocked": false } },
    { "name": "enforced ausente: no se aplica",
      "why": "El default INERTE. Es el estado de HOY y es lo que hace que la regla del #1087 se pudiera deployar sola.",
      "given": { "paywallEnabled": true, "paywallEnforced": null, "isPremium": true },
      "expect": { "blocked": false } },
    { "name": "enforced=false: no se aplica",
      "given": { "paywallEnabled": true, "paywallEnforced": false, "isPremium": true },
      "expect": { "blocked": false } },
    { "name": "free + plantilla paga: FRENA",
      "given": { "paywallEnabled": true, "paywallEnforced": true, "isPremium": true },
      "expect": { "blocked": true } },
    { "name": "free + plantilla de principiante: pasa",
      "why": "La mitad facil de romper de mas. Gatear el catalogo entero deja al free sin nada que entrenar.",
      "given": { "paywallEnabled": true, "paywallEnforced": true, "isPremium": false },
      "expect": { "blocked": false } },
    { "name": "isPremium ausente: se asume gratis",
      "why": "Falla ABIERTO, igual que el @Default(false) de Routine y que firestore.rules. Un error de siembra abre, no cobra.",
      "given": { "paywallEnabled": true, "paywallEnforced": true, "isPremium": null },
      "expect": { "blocked": false } }
  ]
}
```

</details>

El test Dart está en `test/conformance/catalog_gate_conformance_test.dart`,
copiando el patrón de
[`routine_selection_conformance_test.dart`](../test/conformance/routine_selection_conformance_test.dart)
— incluidos los dos guards que ese archivo trae y que valen oro: que el fixture
apunte a la implementación que el test ejercita, y que **no esté vacío** (*"un
fixture sin casos hace que la suite pase sin verificar nada — el modo de falla
más peligroso de este mecanismo"*).

> **El lado Dart ya está resuelto.** La lógica vivía embebida en
> `catalogLockActiveProvider`, que es un `Provider` y por lo tanto no se puede
> ejercitar desde un fixture. Ahora la decisión es `catalogGateBlocks(...)` y el
> provider la llama con `isPremium: true` fijo — que no es un atajo, es la
> definición del provider: "el candado está activo" significa exactamente "una
> plantilla paga le quedaría bloqueada".
>
> El puente entre el enum y el tri-estado del contrato es
> `AthleteEntitlement.paywallEnforced` (`entitled`→false, `free`→true,
> `unknown`→**null**). Ese `null` es lo que hace que "no se sabe" viaje como tal
> hasta la decisión, en vez de que cada plataforma elija su propio default.

### Paso 2 — el dato hasta la pantalla

1. `RoutineSummary` gana `isPremium: Bool`, y `summary(_:origin:)` lo llena con
   `FS.bool(doc.fields["isPremium"]) ?? false`.
2. Una fuente de entitlement: leer `users/{uid}` por REST y quedarse con
   `athletePaywallEnforced`. **Cachearlo por sesión de app** — el camino crítico
   es un tap en un reloj y no puede pagar una ronda de red extra cada vez.
3. Cablear la función del fixture.

### Paso 3 — los dos puntos de arranque

Son dos, igual que en Wear, y hay que cerrar los dos:

| camino | dónde |
|---|---|
| el "Empezar" de HOY | [`ContentView.swift:224`](../ios/TreinoWatch%20Watch%20App/ContentView.swift) |
| el "Empezar" de la lista | [`RoutineListView.swift:284`](../ios/TreinoWatch%20Watch%20App/RoutineListView.swift) |

`RoutineListView` ya tiene dónde poner el mensaje: la vista de detalle muestra
`errorMessage` cuando `failed`
([`RoutineListView.swift:260-263`](../ios/TreinoWatch%20Watch%20App/RoutineListView.swift)),
y `startNow()` ya usa ese canal para *"Esta rutina no tiene ejercicios para
hoy"*. El gate entra ahí, con el mismo patrón.

Texto sugerido, espejo del de Wear (`WearStrings.plantillaPaga`):

> Esta plantilla es del plan pago.
> Mirala en el teléfono.

Nombra el teléfono a propósito: el checkout no existe en el reloj y no va a
existir, así que mandarlo a "ver el plan" ahí sería prometerle una salida que
esa pantalla no tiene.

### Paso 4 — renderizar `syncError`

El más chico y el que más vale por línea. Un banner en `WorkoutView`, al lado
del de `closeFailure`, cuando `syncError != nil`.

**No hace falta distinguir sin-red de rechazo como en Wear**, y ésa es la buena
noticia: el watchOS usa `async throws` y sólo llega ahí cuando la petición REST
falló de verdad, mientras que en Dart un `Future` sin red queda pendiente. Acá
`syncError` ya es la señal correcta — le falta pantalla, nada más.

---

## 4. Qué NO hacer

Cuatro trampas que ya costaron tiempo en las piezas anteriores.

1. **No gatees el `finish`.** La regla del #1087 gatea **sólo el create**, a
   propósito: cerrar un entreno que ya existe no puede depender de un derecho
   que se pudo vencer en el medio, o le borrás un entrenamiento que la persona
   de verdad hizo. El reloj tiene que respetar la misma asimetría. Hay tres
   tests en `scripts/rules_test/athlete-paywall-sessions.test.js` que lo fijan.

2. **No falles cerrado.** Si el entitlement no se pudo leer —red, timeout, doc
   ausente— **dejá pasar**. Es lo que hacen el teléfono
   (`AthleteEntitlement.unknown` no gatea), el Wear y la propia regla. En un
   reloj, con la red del teléfono de por medio, ese caso es mucho más común que
   en la app. El servidor rebota igual si no corresponde.

3. **No copies el gate en cada call site.** Son dos hoy y van a ser más. Una
   función, dos llamadas — es lo que hace que el fixture sirva de algo.

4. **No agregues casos al fixture copiando lo que la implementación devuelve
   hoy.** Corolario explícito del README de conformance. El fixture decide quién
   está mal, no al revés.

---

## 5. Cómo saber que está listo

- [ ] `conformance/catalog_gate.json` existe, con casos, y `Conformance (Swift)`
      lo corre en verde
- [ ] `test/conformance/catalog_gate_conformance_test.dart` en verde
- [ ] Los dos puntos de arranque del watchOS gatean, y un free ve el mensaje
      en vez de arrancar
- [ ] Un free entrena una plantilla de principiante sin fricción — el control
      negativo, el más fácil de romper de más
- [ ] `syncError` se ve en pantalla
- [ ] **Verificación por mutación**: revertí cada pieza dejando los tests y
      confirmá que se ponen rojos. Un fixture que pasa con el gate desconectado
      no está probando el gate.

Con eso, y sólo con eso, se puede:

1. Encender la CF que escribe `athletePaywallEnforced: true`
2. Poner `kAthletePaywallEnabled = true`

En ese orden. El servidor primero, el cliente después: al revés, el cliente
gatea cosas que el servidor todavía permite y el alumno ve un candado que no
corresponde.
