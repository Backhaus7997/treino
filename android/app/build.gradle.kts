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
