import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.treino.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.treino.app"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // El companion de Wear OS es OTRO APK, que se instala en el reloj. La doc de
    // Google es explícita: "Wear OS APKs are separate from mobile APKs, and are
    // uploaded and updated independently from within the Play Console."
    //
    // Se separa por flavor y no por proyecto aparte para no duplicar pubspec, CI
    // ni el arbol Dart: el companion reusa la capa de dominio TAL CUAL (medido:
    // 22/22 casos del contrato de `conformance/` corriendo en el reloj, con cero
    // cambios en lib/features/workout/domain/).
    flavorDimensions += "device"
    productFlavors {
        create("phone") {
            dimension = "device"
        }
        create("wear") {
            dimension = "device"
            // Wear OS 3 = API 30. Por debajo no existe el Wear OS moderno.
            minSdk = 30
            // NADA de applicationIdSuffix: la Data Layer API exige que reloj y
            // teléfono compartan applicationId Y clave de firma. Con un sufijo,
            // el handoff de credencial deja de funcionar y el sintoma aparece
            // lejos de la causa.
        }
    }

    signingConfigs {
        // Credenciales de la upload key, leídas de android/key.properties
        // (gitignored — nunca se commitea). Sólo se declara el config si el
        // archivo existe, para no romper a quien no tiene el keystore.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Con key.properties presente firma con la upload key (único
            // artefacto que Play acepta). Sin el archivo cae a las debug keys
            // para que `flutter run --release` siga funcionando localmente.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// El reloj no dibuja NI UNA imagen de ejercicio. La pantalla HOY lista nombres
// (denormalizados en `RoutineSlot.exerciseName`) y la de entreno muestra series.
// Medido con rg sobre `lib/features/watch/`: cero `Image.asset`, cero
// `AssetImage`, cero `rootBundle`.
//
// Pero `pubspec.yaml` declara los assets de forma global, sin distincion por
// flavor, asi que el APK del reloj se llevaba entero el catalogo del telefono:
// 18.20 MiB de `assets/exercises` (26 PNGs; `plank.png` sola pesa 2.80 MiB) +
// 8.46 MiB de `assets/muscles` (11 PNGs). Van `Stored` en el zip, sin comprimir,
// asi que el peso del APK baja exactamente esos 26.66 MiB.
//
// Medido con builds LIMPIOS de `--flavor wear --target-platform android-arm64`
// (el APK que se instala al reloj), antes -> despues:
//   debug   153.33 MiB -> 126.67 MiB  (-17.4%)
//   profile  93.53 MiB ->  66.87 MiB  (-28.5%)
//
// OJO al medir: `ls -l` sobre un APK RE-empaquetado miente. AGP repackagea
// incremental —reemplaza entradas en el lugar y deja huecos de ceros— asi que un
// APK incremental daba 281.70 MiB con 128.44 MiB de gaps internos. Comparar
// siempre builds limpios, o sumar los tamanios comprimidos de `unzip -v`.
//
// Se excluyen del `Copy` que inyecta `flutter_assets` dentro de los merged
// assets del variant. El scope al reloj es POR CONSTRUCCION: la tarea se llama
// `copyFlutterAssets${variant}` (FlutterPlugin.kt), o sea que el nombre lleva el
// flavor adentro y el flavor `phone` no se entera de nada.
//
// Se hace aca y NO con `androidResources.ignoreAssetsPattern` por dos razones:
// ese patron es global en AGP —no admite scope por variant— y encima corre
// durante el merge de assets, mientras que `flutter_assets` los inyecta esta
// tarea DESPUES del merge.
//
// OJO con lo que NO se saca: `assets/fonts/` se queda. `main_wear.dart` importa
// `app/theme/app_theme.dart`, que usa `GoogleFonts.barlow*`, y google_fonts
// resuelve las familias buscandolas en el AssetManifest. Sin las fuentes
// bundleadas se las baja por red, que es justo lo que el pubspec viene a evitar.
//
// Sabido y aceptado: `AssetManifest.bin` lo genera la herramienta de Flutter
// antes de esta tarea, asi que sigue listando las PNGs que aca se sacan. En el
// reloj es inofensivo porque nadie las busca nunca. Si algun dia la UI del reloj
// dibuja una imagen, el sintoma va a ser un asset faltante en runtime, no un
// error de build.
val phoneOnlyAssetPatterns =
    listOf(
        "flutter_assets/assets/exercises/**",
        "flutter_assets/assets/muscles/**"
    )

tasks.withType<Copy>().configureEach {
    if (name.startsWith("copyFlutterAssetsWear")) {
        exclude(phoneOnlyAssetPatterns)
    }
}

// `copyFlutterAssets{Variant}` es un detalle interno del plugin de Gradle de
// Flutter. Si un upgrade lo renombra, el `configureEach` de arriba deja de
// matchear EN SILENCIO y el APK del reloj vuelve a cargar los ~27 MB de imagenes
// sin que nadie se entere. Este chequeo lo convierte en un build roto, que es lo
// que corresponde: si empaquetas el reloj, la exclusion existe o no hay build.
gradle.taskGraph.whenReady {
    val wearVariantsBeingPackaged =
        allTasks
            .mapNotNull {
                Regex("^package(Wear(?:Debug|Profile|Release))$").find(it.name)?.groupValues?.get(1)
            }.toSet()
    wearVariantsBeingPackaged.forEach { variant ->
        val copyTaskName = "copyFlutterAssets$variant"
        check(allTasks.any { it.name == copyTaskName }) {
            "No se encontro la tarea `$copyTaskName` en el task graph. La exclusion de " +
                "assets del flavor `wear` (android/app/build.gradle.kts) cuelga de ese " +
                "nombre, que es interno del plugin de Gradle de Flutter. Si un upgrade lo " +
                "renombro, actualiza el prefijo `copyFlutterAssetsWear` — sin eso el APK " +
                "del reloj se lleva ~27 MB de imagenes que no usa."
        }
    }
}

dependencies {
    // `wearImplementation` = SOLO el flavor `wear`. El APK del teléfono no
    // carga nada de esto: no tiene sensores de muñeca ni corre entrenos.
    //
    // Health Services es el equivalente de HealthKit en Wear OS. Es lo que
    // provee pulsaciones y calorías durante el entreno. OJO con lo que NO
    // hace: NO mantiene vivo el proceso. Trackea en el MCU, fuera de nuestro
    // proceso, y nos entrega datos — mantener la app viva es trabajo del
    // WorkoutForegroundService, y eso ya está medido (22.6% de cobertura sin
    // el servicio, 100.0% con él).
    //
    // 1.0.0 es la última ESTABLE. La última publicada es 1.1.0-rc02; se
    // arranca en estable y se evalúa después.
    "wearImplementation"("androidx.health:health-services-client:1.0.0")
}

flutter {
    source = "../.."
}
