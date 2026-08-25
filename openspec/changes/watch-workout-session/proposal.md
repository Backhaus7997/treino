# Propuesta — el reloj como app de entrenamiento de verdad

**Change**: `watch-workout-session`
**Rama sugerida**: `feat/watch-workout-session`
**Depende de**: `watch-standalone-client` (el companion ya existe y funciona)

---

## 1. Intención

Que watchOS trate a TREINO como una **app de entrenamiento**, abriendo un
`HKWorkoutSession` mientras dura el entreno.

El pedido que originó esto fue el ritmo cardíaco. La investigación
(`explore.md`) mostró que las pulsaciones son la parte visible de un mecanismo
que además arregla el bug más grave que queda: **el descanso muere cuando el
atleta baja la muñeca**.

Se plantea al revés de como suena el pedido: no "agregar pulsaciones", sino
**que el reloj se comporte como corresponde**, con el ritmo cardíaco como
consecuencia.

---

## 2. Por qué ahora

Tres cosas medidas en el código, no supuestas:

1. **El descanso es un `Timer` común** (`WorkoutCoordinator.swift:444`) y el
   target del reloj **no declara ningún background mode**. En el gimnasio,
   bajar el brazo es el caso normal.
2. **La duración es reloj de pared** en los dos lados. El teléfono ya necesitó
   un parche (`maxWorkoutDuration`) por sesiones dejadas abiertas toda la
   noche.
3. **No hay ningún dato de esfuerzo.** El volumen es la única métrica.

---

## 3. Alcance

### Entra

- Entitlement + capability de HealthKit en el target del reloj
- Permisos: solicitud, y comportamiento correcto cuando el atleta los niega
- `HKWorkoutSession` abierta y cerrada junto con el entreno
- Ritmo cardíaco en vivo en la pantalla de entreno
- Duración tomada de la sesión de entrenamiento en vez de calculada
- Escritura del entreno en la app Salud

### No entra

- HealthKit en el teléfono — los sensores están en el reloj
- Zonas de frecuencia cardíaca, VO2, recuperación
- Anillos de actividad de Apple
- Wear OS
- Retos / Missions / Bets / Gamificación (prohibidos en todo el producto)

---

## 4. Decisiones a firmar

Ninguna está tomada. Van con recomendación, pero las firma el dueño.

### D1 — ¿Dónde vive el ritmo cardíaco?

- **(a) Solo en pantalla y en Salud** ← recomendada
- (b) También un resumen en Firestore (promedio y máximo por sesión)
- (c) Solo en pantalla, sin escribir nada

**Por qué (a):** el atleta ya tiene sus pulsaciones en Salud, que es donde las
busca un usuario de Apple Watch. La opción (b) arrastra esquema en Firestore,
Security Rules, UI en el teléfono y una decisión de privacidad sobre si el PF
ve la frecuencia cardíaca de sus atletas — eso último merece su propio ciclo,
no ir de arrastre.

### D2 — ¿Qué pasa si niega el permiso?

Recomendada: **el entreno funciona igual, sin pulsaciones y sin degradar nada
más**. A verificar en F0 si la sesión de entrenamiento —y con ella la
ejecución en segundo plano— se puede abrir sin permiso de LECTURA de HR. Si no
se puede, hay que decidir si se insiste con el permiso o se acepta que ese
usuario pierde el descanso en segundo plano.

### D3 — ¿Se escribe el entreno en la app Salud?

Recomendada: **sí**. Es lo que espera un usuario de Apple Watch, y sin eso el
entreno de TREINO no cuenta para sus anillos ni su historial. Necesita permiso
de escritura, aparte del de lectura.

### D4 — ¿Qué pasa con la duración que ya guardamos?

Recomendada: **la sesión de entrenamiento pasa a ser la fuente de verdad
cuando existe**, y el cálculo actual queda como respaldo. El campo
`durationMin` en Firestore no cambia de forma — cambia de dónde sale el número.

---

## 5. Fases

Ordenadas para que **el valor grande se pueda verificar lo antes posible**, y
lo que solo se prueba en hardware quede acotado y al final.

### F0 — Terreno y permisos

Entitlement, capability, textos de permiso, y la solicitud. Sin sesión de
entrenamiento todavía.

**Cierra cuando:** el reloj compila con HealthKit habilitado, pide permiso, y
el entreno sigue funcionando exactamente igual con permiso concedido y
denegado.

**Responde además tres preguntas abiertas del explore:** si hace falta
regenerar el provisioning profile, si `HKWorkoutSession` corre en el
simulador, y si la sesión se puede abrir sin permiso de lectura de HR.

### F1 — La sesión de entrenamiento — **el corazón del ciclo**

Abrir `HKWorkoutSession` al empezar y cerrarla al terminar. **Sin tocar el
ritmo cardíaco todavía.**

**Cierra cuando:** el descanso sobrevive a bajar la muñeca y a que se apague
la pantalla.

Va sola en una fase a propósito: es el arreglo que justifica el ciclo, y es
verificable **sin pulsaciones**. Si el hardware demora, esto ya está entregado.

### F2 — Ritmo cardíaco en vivo

`HKLiveWorkoutBuilder`, y las pulsaciones en la pantalla de entreno.

**Cierra cuando:** se ve el número latiendo en un Apple Watch real.

**Solo verificable en hardware.**

### F3 — Duración y escritura en Salud

La duración pasa a salir de la sesión de entrenamiento, y el entreno se
escribe en Salud.

**Cierra cuando:** un entreno de TREINO aparece en la app Salud con su
duración correcta.

---

## 6. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| **El simulador no da ritmo cardíaco** | Alto — rompe el modo de trabajo del ciclo anterior, donde todo se verificó en simulador | F1 entrega el valor grande y es verificable sin HR. F2/F3 se agrupan para un solo smoke en hardware. |
| El entitlement exige regenerar el provisioning profile | Medio — bloquea builds hasta resolverlo | Se ataca en F0, antes de escribir lógica |
| Apple pide declaraciones de privacidad por HealthKit | Medio — aparece recién en la review | Confirmar el alcance real en F0 |
| El atleta niega el permiso | Medio — sin background, el descanso vuelve a morir | D2. El entreno nunca puede dejar de funcionar |
| Dos apps escribiendo el mismo entreno en Salud | Bajo — hoy el teléfono no escribe nada en Salud | Solo el reloj escribe |

---

## 7. Lo que NO cambia

- La arquitectura REST del reloj. HealthKit es local, no toca Firestore.
- La sincronía con el teléfono, que quedó verificada en el ciclo anterior.
- El contrato de conformidad Dart↔Swift.
- El esquema de Firestore, salvo que se firme D1(b).

---

## 8. Nota de método

El ciclo anterior dejó una lección que aplica directo acá: **cada vez que se
declaró algo listo sin verlo correr, estaba mal**. Y acá el simulador deja de
alcanzar.

Por eso las fases están ordenadas por *verificabilidad*, no por dependencia
técnica: F1 entrega el arreglo importante y se puede probar; F2 y F3 se
agrupan para un único smoke en hardware en vez de quedar bloqueadas de a una.
