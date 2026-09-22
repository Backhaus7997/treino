# Capturas de tienda — semilla y receta

Todo lo que hace falta para **regenerar el set de capturas de App Store desde
cero**, sin cargar un solo dato a mano.

Vivía fuera del repo (`~/treino-shots/seed/`), o sea en una sola máquina. Eso
contradice la regla 10c de [AGENTS.md](../../AGENTS.md) —lo que tiene que
sobrevivir a tu sesión va a un archivo del repo— y hacía imposible el objetivo
declarado del set: poder regenerarlo igual dentro de seis meses.

## Todos los scripts son EMULATOR-ONLY

Cada uno aborta si no encuentra `FIRESTORE_EMULATOR_HOST`. Ninguno lee
`.firebaserc`, ninguno toma credenciales de producción: hablan por HTTP con el
emulador y nada más. Ver el banner de Entornos de `AGENTS.md`.

## API modular, no namespaced — y corré `npm ci` antes de creerle a tu local

Estos scripts usan `require('firebase-admin/app')` y
`require('firebase-admin/firestore')`. **No** `const admin =
require('firebase-admin')` con `admin.firestore()` y
`admin.firestore.Timestamp`: **firebase-admin 14 borró la API namespaced
entera**, y el repo pinea `^14.3.0`.

Lo cubre `scripts/test/firebase_admin_superficie.test.js`, que escanea
`scripts/` **recursivo** —o sea que este directorio también entra— y falla si un
script usa una API que la versión instalada no expone.

⚠️ **La trampa que este README existe para que no repitas.** Al traer estos
scripts al repo pasaron los tests en local y CI los puso en rojo igual: mi
`scripts/node_modules` tenía **12.7.0**, dos majors atrás del lockfile, y en esa
versión `admin.firestore()` todavía existía. El local decía verde sobre una
dependencia que nadie más tiene.

```bash
# la versión que CI va a usar, no la que quedó de antes
npm --prefix scripts ci
node -e "console.log(JSON.parse(require('fs').readFileSync('scripts/node_modules/firebase-admin/package.json','utf8')).version)"
```

Y un guard en verde tampoco prueba que el script **funcione**: después de
migrar, corré los siete contra el emulador y mirá que impriman lo de siempre.

## Receta completa

```bash
# 1. Emulador. Desde el #1214 se busca el JDK 21 solo (`scripts/lib/java21.sh`),
#    así que no hace falta exportar JAVA_HOME a mano — con Java 17 en el PATH
#    firebase-tools 15 no arranca y antes había que pasárselo.
SKIP_FUNCTIONS=1 ./scripts/emulator.sh

# 2. Semilla base del repo
FIRESTORE_EMULATOR_HOST=localhost:8080 \
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
  node scripts/seed_emulator_full.js

# 3. Capa de capturas, EN ESTE ORDEN
cd scripts/capturas
for s in seed_capturas_store.js add_rutinas.js plantilla_ppl.js \
         sesion_hoy_martin.js entrenaron_hoy.js seed_cobros_pendientes.js \
         turnos_futuros.js; do
  FIRESTORE_EMULATOR_HOST=localhost:8080 node "$s"
done
```

| script | qué deja en pantalla |
|---|---|
| `seed_capturas_store.js` | 12 meses de historial (el reporte mensual dibuja 12 barras fijas) + vínculos del PF |
| `add_rutinas.js` | las rutinas del alumno en la tab Entrenar |
| `plantilla_ppl.js` | la plantilla «Fuerza PPL» del PF |
| `sesion_hoy_martin.js` | una sesión de HOY, para que la racha no caiga en empty state |
| `entrenaron_hoy.js` | la lista «ENTRENARON HOY» del dashboard del PF |
| `seed_cobros_pendientes.js` | «PAGOS POR COBRAR» con importes reales en vez de «Sin cobros pendientes» |
| `turnos_futuros.js` | «PRÓXIMAS SESIONES» del PF, a futuro |

## El seed se vence en días — recorrelo siempre

Tres de estos scripts escriben fechas **relativas al día en que se corren**. Si
reusás un emulador de hace una semana, la pantalla se cae sola en empty states,
que es exactamente lo que una captura de tienda no puede mostrar:

| qué se rompe | por qué |
|---|---|
| «RACHA ACTUAL 11 días» → «TU RACHA TE ESPERA» | el seed reparte los días dentro del mes en curso; al cruzar el lunes arranca una semana sin sesiones |
| «PRÓXIMAS SESIONES» → «No tenés turnos próximos confirmados» | los turnos vencen |
| «PAGOS POR COBRAR» → «Sin cobros pendientes» | ídem |

**Y reseedear no alcanza: hay que REINICIAR la app.** Los providers de racha e
insights cachean, y el pull-to-refresh del Home no los recalcula.

```bash
xcrun simctl terminate <UDID> com.backhaus.treino
flutter run -d <UDID> --dart-define=USE_EMULATOR=true
```

## Trampa: vínculos duplicados

El seed base y `seed_capturas_store.js` crean **cada uno** su vínculo para los
mismos alumnos (`seed-link-001` y `cap-link-001` apuntan los dos a
`seed-athlete-001`, los dos `active`). `pagosPorCobrarProvider` itera
**vínculos**, no alumnos, así que un alumno con dos vínculos facturables
aparece **dos veces** en «PAGOS POR COBRAR» con el mismo importe.

`seed_cobros_pendientes.js` lo esquiva facturando sólo alumnos con exactamente
un vínculo facturable, y avisa por consola cuáles saltea. **No está arreglado
en la app**: si algún día el producto puede generar ese estado con datos
reales, el PF ve cobros duplicados.

## Simulador

El slot que pide App Store Connect para esta ficha es **iPhone 6.5"**, y el
simulador que captura **1284 × 2778 exacto, sin reescalar**, es el **iPhone 14
Plus**. No viene instanciado por defecto en Xcode 26/27, pero el device type sí
existe:

```bash
UDID=$(xcrun simctl create "TREINO-captura-6.5" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$UDID"

xcrun simctl status_bar "$UDID" override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState discharging --batteryLevel 100
xcrun simctl ui "$UDID" appearance dark
```

`--batteryState charged` dibuja el **rayo de carga**; para la batería llena y
limpia va `discharging` con level 100.

**El PNG del simulador sale CON alfa y App Store lo rechaza.** Hay que sacarlo,
y conviene verificarlo en vez de asumirlo:

```bash
magick "$f" -background black -alpha remove -alpha off -strip "$f"
sips -g hasAlpha "$f"     # tiene que decir: no
```

## Chequeo final del set

```bash
for f in store/ios/screenshots/es-MX/iphone-6.5/*.png; do
  w=$(sips -g pixelWidth  "$f" | tail -1 | awk '{print $2}')
  h=$(sips -g pixelHeight "$f" | tail -1 | awk '{print $2}')
  a=$(sips -g hasAlpha    "$f" | tail -1 | awk '{print $2}')
  printf '%-22s %sx%s alfa=%s\n' "$(basename "$f")" "$w" "$h" "$a"
done
```

Las 9 tienen que dar `1284x2778 alfa=no`. Una sola distinta y App Store Connect
rechaza el set entero.

⚠️ No armes ese chequeo con `rg -o '[0-9]+'` sobre la ruta completa: matchea
también los dígitos del **path** y reporta que todas son distintas. Pasó.
