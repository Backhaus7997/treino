# Exploración — el reloj como app de entrenamiento de verdad

Disparador: el dueño preguntó por el **ritmo cardíaco**. La investigación
mostró que las pulsaciones son la parte visible de algo más de fondo, y que
ese fondo ya nos está costando bugs.

---

## 1. Qué hay hoy

El companion watchOS existe y funciona (ciclo `watch-standalone-client`, 45
commits). Lee la rutina por REST, carga series, sincroniza con el teléfono en
las dos direcciones y termina el entreno.

Pero **para watchOS es una app común que muestra un entrenamiento**, no una
app de entrenamiento. La diferencia no es semántica: el sistema trata distinto
a las dos.

### Verificado leyendo el código

| Qué | Estado | Dónde |
|---|---|---|
| HealthKit | **cero referencias** en `lib/` y en el target del reloj | — |
| Entitlements | solo `aps-environment` y `applesignin` | `ios/Runner/Runner.entitlements` |
| Background modes del reloj | **ninguno** — el pbxproj solo declara `WKCompanionAppBundleIdentifier` | `project.pbxproj:560,607,651` |
| Descanso | `Timer.scheduledTimer` común | `WorkoutCoordinator.swift:444` |
| Duración (reloj) | `Date().timeIntervalSince(start)` — reloj de pared | `WorkoutCoordinator.swift:396` |
| Duración (teléfono) | `elapsedSeconds` acotado por `maxWorkoutDuration` | `session_notifier.dart:747` |

Y el proposal del ciclo anterior lo dejó **explícitamente fuera de alcance**:
`openspec/changes/watch-standalone-client/proposal.md:38` — "HealthKit / heart
rate / biométricos".

---

## 2. El problema real, que no es el ritmo cardíaco

### 2.1 El descanso muere si bajás la muñeca

`restTimer` es un `Timer` de Foundation. Sin background modes declarados,
watchOS **suspende la app** cuando el atleta baja el brazo o la pantalla se
apaga. El timer deja de correr.

En el gimnasio eso es el caso NORMAL, no el borde: nadie se queda mirando el
reloj durante 3 minutos de descanso.

Es el bug más grave de los que quedan, y no se puede arreglar con más código
Swift: **se arregla declarándole al sistema que esto es un entrenamiento**.

### 2.2 La duración es una estimación, no una medición

Los dos lados calculan duración restando timestamps. El teléfono ya tuvo que
poner un parche: `maxWorkoutDuration` acota sesiones dejadas abiertas toda la
noche (`sanitizedActiveSessionElapsedSeconds`). Es un síntoma de que nadie
está midiendo de verdad cuánto duró el entreno.

### 2.3 No hay ningún dato biométrico

Ni pulsaciones, ni calorías, ni zonas. El volumen (`reps × kg`) es la única
métrica, y no dice nada del esfuerzo real.

---

## 3. El mecanismo

En watchOS todo esto sale de **una** cosa: abrir un `HKWorkoutSession`
mientras dura el entreno.

Eso le dice al sistema "esto es una app de entrenamiento", y a cambio:

- **Ejecución en segundo plano** mientras la sesión está viva → el descanso
  sobrevive a bajar la muñeca
- **Ritmo cardíaco en vivo**, vía `HKLiveWorkoutBuilder`
- **Duración y calorías medidas por el reloj**, no calculadas por nosotros
- Comportamiento correcto con la pantalla siempre encendida

O sea: el ritmo cardíaco es **una consecuencia** del arreglo, no el objetivo.
Encarar solo "mostrar pulsaciones" dejaría el bug del descanso sin tocar.

---

## 4. Lo que hay que decidir antes de escribir código

### 4.1 ¿Dónde vive el ritmo cardíaco?

Tres opciones con consecuencias muy distintas:

- **Solo en Salud** — el reloj escribe el workout en HealthKit y listo. Cero
  cambios en Firestore, cero cambios en el teléfono. El atleta ve sus
  pulsaciones en la app Salud, no en TREINO.
- **Solo en pantalla** — se muestran en vivo durante el entreno y no se
  guardan en ningún lado nuestro.
- **También en Firestore** — resumen por sesión (promedio, máximo) para que el
  teléfono y el PF lo vean. Implica esquema, rules, y UI en el teléfono.

Es la decisión de mayor alcance del ciclo.

### 4.2 ¿Qué pasa si el atleta niega el permiso?

HealthKit exige permiso explícito. **La app tiene que seguir funcionando
igual** — el entreno no puede depender de eso. Pero entonces el descanso vuelve
a morir en segundo plano para ese usuario, salvo que la sesión de entrenamiento
se pueda abrir sin permiso de lectura de HR (a verificar).

### 4.3 ¿Se escribe el entreno en la app Salud?

Distinto de leer pulsaciones. Escribir el workout en Salud es lo que espera un
usuario de Apple Watch, y necesita permiso de escritura aparte.

---

## 5. El riesgo que define el ciclo

**El simulador no genera ritmo cardíaco.**

Todo lo que se verificó en el ciclo anterior fue en simulador, y funcionó. Acá
eso se termina: hace falta **un Apple Watch real en la muñeca** para probar
pulsaciones, y probablemente también para el comportamiento en segundo plano.

Esto cambia cómo hay que planificar las fases: conviene que el valor grande
—que el descanso sobreviva— sea verificable lo más temprano posible, y que lo
que solo se pueda probar en hardware quede acotado y al final.

### Otros riesgos, a verificar en la primera fase

- El entitlement de HealthKit **probablemente** exige regenerar el
  provisioning profile. No confirmado.
- Apple pide declaraciones de privacidad para apps con HealthKit en la review.
  Alcance real sin confirmar.
- Si `HKWorkoutSession` corre o no en el simulador (aunque sin datos de HR)
  está **sin verificar** — determina cuánto se puede probar sin hardware.

---

## 6. Lo que NO entra

- HealthKit en el **teléfono**. El reloj es el que tiene los sensores.
- Zonas de frecuencia cardíaca, VO2, recuperación. Métricas derivadas, otro
  ciclo.
- Anillos de actividad de Apple.
- Wear OS — sigue fuera, misma razón que el ciclo anterior.
