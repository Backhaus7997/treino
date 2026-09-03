# Publicar el companion de Wear OS

Todo esto se hace **desde macOS**. Flutter y Gradle generan el bundle igual que
en Windows; no hace falta cambiar de máquina.

## Lo que ya está listo en el repo

- **`versionCode` propio para el reloj.** Play distribuye los dos artefactos
  bajo el MISMO `applicationId` —los separa por `uses-feature watch`— y exige
  que cada uno tenga su número. Con el mismo `versionCode`, el segundo que
  subas se rechaza. El flavor `wear` suma 1000: el teléfono va 16, 17… y el
  reloj 1016, 1017…, así que el número dice solo de qué artefacto es.
- **`uses-feature android.hardware.type.watch`** en el manifest del flavor
  `wear`. Es lo que hace que Play lo ofrezca al reloj y NO al teléfono.
- **`minSdk 30`** (Wear OS 3).
- **Firma de release condicionada** a que exista `android/key.properties`.

Verificado sobre el APK de release generado:

    package: com.treino.app  versionCode='1016'
    uses-feature: name='android.hardware.type.watch'

## Lo que falta, y sólo lo podés hacer vos

### 1. La upload key

No está en el repo y no debe estarlo. Se crea una vez:

    keytool -genkey -v -keystore ~/treino-upload.jks \
      -keyalg RSA -keysize 2048 -validity 10000 -alias upload

La contraseña la elegís vos y no va al repo ni al chat. **Guardá el archivo
fuera del proyecto y con backup**: si se pierde, Play no acepta más
actualizaciones de esa app sin un trámite de recuperación.

### 2. `android/key.properties`

Gitignoreado a propósito:

    storePassword=...
    keyPassword=...
    keyAlias=upload
    storeFile=/Users/<vos>/treino-upload.jks

Sin este archivo el build cae a **debug keys** y Play lo rechaza. Comprobalo
antes de subir:

    ~/Library/Android/sdk/build-tools/35.0.0/apksigner verify --print-certs \
      build/app/outputs/flutter-apk/app-wear-release.apk

Tiene que decir tu certificado, NO `CN=Android Debug`.

### 3. Generar el bundle

    flutter build appbundle --release --flavor wear -t lib/main_wear.dart

Sale en `build/app/outputs/bundle/wearRelease/app-wear-release.aab`.

El del teléfono es el mismo comando con `--flavor phone -t lib/main.dart`.

### 4. Subirlo a Play Console

Los dos artefactos van a la MISMA app (`com.treino.app`), en el mismo release
de testing interno. Play decide cuál mandar a cada dispositivo por el
`uses-feature`.

## Lo que cambia cuando esto salga por Play

Dos cosas dejan de doler, y conviene saberlo porque hoy son la fuente de la
mitad de los problemas de esta rama:

1. **La firma pasa a ser la misma en los dos aparatos.** La Data Layer API
   exige mismo `applicationId` **y misma clave**, y hoy el canal está mudo
   justamente porque conviven un teléfono bajado de Play con un reloj
   sideloadeado con debug keys. Saliendo los dos de Play App Signing, comparten
   clave por construcción.

2. **App Check pasa a Play Integrity de verdad**, así que se terminan los debug
   tokens que hay que registrar a mano en la Console cada vez que se borran los
   datos de la app.

## Lo que NO resuelve publicar

El emparejamiento. Que el reloj esté vinculado a ESE teléfono —con la app
companion de Wear instalada— es independiente de cómo se distribuya la app. Sin
eso, la Data Layer sigue sin cruzar y el aviso de arranque llega igual por FCM,
que no depende del emparejamiento.
