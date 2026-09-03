# Medir supervivencia del entreno en un reloj Wear OS FÍSICO

Runbook para la única medición que el emulador no puede dar. Pensado para
ejecutarse de una sentada, con el reloj en la mano.

> **Por qué existe este documento.** Todo el ciclo del companion de watchOS se
> midió en simulador, y eso dejó la pregunta central sin responder durante una
> fase entera. Acá ya sabemos que el emulador de Wear OS **no puede** contestarla:
> no hace suspend-to-RAM, y en ninguna condición probada congeló la app. Un verde
> en emulador es verde falso por construcción.

---

## 0. Lo que NO sirve, para no perder la mañana

**Instalar la app en el teléfono NO instala nada en el reloj.** El companion de
Wear OS es un APK aparte. La doc oficial es explícita:

> "Wear OS APKs are separate from mobile APKs, and are uploaded and updated
> independently from within the Play Console."

**Play Console tampoco lo instala solo.** Cuando el usuario instala la app del
teléfono, al reloj le llega una **notificación** y hay que seguir las
instrucciones en pantalla — instalación manual. Y antes de todo eso habría que
tener el APK del reloj construido, firmado con la clave de release, y subido a un
track. Es un día de ceremonia antes de medir el primer segundo.

**Para medir, side-load por adb.** Sin Play Console, sin firma de release, sin
review.

---

## 1. Preparar el reloj (una sola vez)

1. **Ajustes → Sistema → Acerca de → Versiones** → tocar 7 veces
   **Número de compilación**. Aparece "Ya eres desarrollador".
2. **Ajustes → Opciones para desarrolladores** → activar:
   - **Depuración por ADB**
   - **Depuración por Wi-Fi**
3. Reloj y Mac en **la misma red Wi-Fi**.
4. En "Depuración por Wi-Fi" el reloj muestra su **IP:puerto**. Anotarla.

### Emparejar

Wear OS 3+ usa el emparejamiento con código. En el reloj:
**Opciones para desarrolladores → Depuración inalámbrica → Vincular dispositivo
nuevo** → muestra un código de 6 dígitos y un **puerto de emparejamiento**
(distinto del de conexión).

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

adb pair <IP>:<PUERTO_DE_EMPAREJAMIENTO>     # pide el código de 6 dígitos
adb connect <IP>:<PUERTO_DE_CONEXION>        # el otro puerto
adb devices -l                               # tiene que aparecer el reloj
```

> Si `adb devices` lista también el emulador, **apagarlo** o usar `-s <serial>`
> en todos los comandos. Instalar en el dispositivo equivocado y medir sobre él
> es un error que se ve tarde y se explica peor.

---

## 2. Instalar y medir

```bash
cd /Users/martinbackhaus/treino/.claude/worktrees/wearos-companion
WATCH=<IP>:<PUERTO>

# CONTROL ROJO — sin foreground service
flutter run -d "$WATCH" -t lib/main_wear_liveness_spike.dart

# VERDE esperado — con foreground service
flutter run -d "$WATCH" -t lib/main_wear_liveness_spike.dart --dart-define=FGS=true
```

### Antes de creerle a CUALQUIER número

**1. Confirmar que el binario instalado es el nuevo.** En watchOS una medición
salió mal por instalar antes de que terminara el build.

```bash
adb -s "$WATCH" shell dumpsys package com.treino.app | rg 'lastUpdateTime|versionCode'
```

**2. Confirmar que el reloj PUEDE suspender.** Si no suspende durante la
ventana, la medición no prueba nada — ni verde ni rojo.

```bash
adb -s "$WATCH" shell cat /sys/power/state        # esperar: freeze mem
adb -s "$WATCH" shell cat /sys/power/mem_sleep    # si no lista 'deep', no hay suspend-to-RAM
adb -s "$WATCH" shell cat /sys/power/suspend_stats/success
```

Leer `success` **antes y después** de la ventana. **Delta 0 ⇒ corrida inválida,
repetir.**

**3. Medir DESCONECTADO.** Con USB/adb enumerado, Android sostiene un wakeup
source justamente para adb, y el reloj **no suspende nunca**. Con Wi-Fi debugging
el efecto es menor pero existe. Protocolo: instalar, **quitar la muñeca del
cargador y dejar el reloj quieto**, medir, y recién después
`adb -s "$WATCH" logcat -d` para levantar el buffer.

**4. Ventanas de 5 minutos, no de 90 segundos.** Doze light tarda minutos y el
modo ambient sostiene wakelocks.

---

## 3. La matriz — espejo de la de watchOS

Muñeca baja, 300 s, reloj desconectado:

| # | ForegroundService | ExerciseClient | predicción |
|---|---|---|---|
| A | ❌ | ❌ | **ROJO** — línea base |
| B | ✅ `health` | ❌ | **VERDE en timer, ROJO en datos** |
| C | ❌ | ✅ | **ROJO** — a los 5 min, `AUTO_END_MISSING_LISTENER` |
| D | ✅ | ✅ | **VERDE en todo** |

Hoy están implementadas A y B (`--dart-define=FGS=false|true`). C y D necesitan
`ExerciseClient`, que **no está escrito todavía**.

**La celda que decide es B.** En watchOS las dos mitades hacían lo mismo y las
cuatro combinaciones dieron 3 rojos y 1 verde. Acá la predicción es que **B da
verde en supervivencia**, porque la mitad que mantiene vivo el proceso es sólo el
foreground service — Health Services trackea en el MCU, fuera de nuestro proceso,
y no mantiene vivo nada.

**Si B sale ROJO, el modelo mental está mal y hay que replanificar antes de
seguir construyendo encima.**

---

## 4. Cómo se lee el log

Cada tick imprime:

```
[LIVE] n=183 tick=183 skipped=0 boot=183200 uptime=183200 wall=183200 suspend=0 rest=417000
```

| observación | diagnóstico |
|---|---|
| `boot` avanza, `uptime` avanza, faltan callbacks | proceso DESPIERTO pero hambreado (freezer / throttling) |
| `boot` avanza, `uptime` **NO** avanza | **suspensión real del SoC** ← lo que el emulador nunca mostró |
| `boot ≈ uptime ≈ wall`, sin callbacks faltantes | verde |
| `wall` salta y `boot` no | sync de hora con el teléfono, no suspensión |

Analizador:

```bash
flutter run -d "$WATCH" -t lib/main_wear_liveness_spike.dart --dart-define=FGS=true 2>&1 | tee /tmp/wear.log
python3 scripts/analyze_wear_liveness.py /tmp/wear.log
```

Si el `flutter run` se corta (por ejemplo si matás el proceso a mano), el log
sigue yendo a logcat:

```bash
PID=$(adb -s "$WATCH" shell pidof com.treino.app | tr -d '\r')
adb -s "$WATCH" logcat -d --pid="$PID" | rg 'LIVE\]'
```

**Criterio de aceptación**: ≤ 2 s perdidos en 300 s — el mismo margen que el
"1 s en 58" que dio verde en watchOS.

---

## 5. El test del descanso, que es independiente de todo lo anterior

El descanso está implementado por **deadline persistido**, no por conteo de
ticks. Se prueba solo, y **no necesita** que el keep-alive funcione:

```bash
# con el descanso corriendo, matar el proceso a mano
adb -s "$WATCH" shell am force-stop com.treino.app
# reabrir
adb -s "$WATCH" shell am start -n com.treino.app/.MainActivity
```

En el log tiene que decir `descanso RESTAURADO` con el restante **correcto**.
Un contador de ticks arrancaría de cero acá. Éste es el control que justifica el
deadline frente a quien diga "con el foreground service alcanzaba".

---

## 6. Lo que sigue sin resolver

1. **Estructura de build.** No hay flavor `wear` ni `<uses-feature
   android:hardware.type.watch>`. El APK actual se instala y corre en un reloj
   (verificado en emulador), pero no está marcado como app de reloj — hace falta
   para el launcher y para Play Store. **No bloquea la medición de mañana.**
2. **`ExerciseClient` no está escrito.** Sin él no hay pulsaciones, ni calorías,
   ni duración medida. Bloquea las celdas C y D de la matriz.
3. **`android/key.properties` no existe en esta máquina.** Reloj y teléfono
   tienen que compartir clave de firma para que `watch_connectivity` funcione.
   Para side-load con debug keys alcanza (mismo keystore de debug), pero para
   cualquier cosa vía Play Console es bloqueante.
4. **El `FlutterEngine` y el timeout de ambient de Wear OS 5.** Si el sistema
   destruye la Activity, `flutterEngine.destroy()` se lleva el isolate y el
   foreground service NO lo protege — protege al proceso, no al engine.
   Mitigación probable: cached engine. **Sin verificar.**
