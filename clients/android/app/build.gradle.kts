// Kept in step with :core — an APK can only split along the ABIs whose Swift
// core was actually staged. See core/build.gradle.kts.
val androidAbis: List<String> =
    (providers.gradleProperty("mozz.swiftArchs").orNull ?: "aarch64")
        .split(",").map { it.trim() }.filter { it.isNotEmpty() }
        .map { mapOf("aarch64" to "arm64-v8a", "x86_64" to "x86_64")[it] ?: error("unmapped arch '$it'") }

// The version is resolved by `tools/version-info.py`, the same script the desktop
// csproj calls and the same `MARKETING_VERSION` the Apple project declares.
//
// Android used to carry a hardcoded `0.1.0` / `versionCode 1` while the other two
// platforms were on CalVer, so one tag produced three different answers to "what
// version are you running" — which makes a bug report impossible to place against
// a commit. Reading the shared script is what keeps one release one number.
//
// `versionCode` has to be a monotonically increasing integer, and the build number
// is `git rev-list --count HEAD`, which is exactly that. A dirty tree appends a
// `.n` dev suffix, so take the part before the dot.
fun resolvedVersion(field: String, fallback: String): String {
    val script = rootProject.projectDir.resolve("../../tools/version-info.py").normalize()
    if (!script.exists()) return fallback
    return runCatching {
        val process = ProcessBuilder("python3", script.absolutePath, "--field", field)
            .redirectErrorStream(false)
            .start()
        val output = process.inputStream.bufferedReader().readText().trim()
        if (process.waitFor() != 0 || output.isEmpty()) fallback else output
    }.getOrDefault(fallback)
}

val mozzVersionName: String = resolvedVersion("marketing", "0.0.0")
val mozzVersionCode: Int =
    resolvedVersion("build", "1").substringBefore('.').toIntOrNull() ?: 1

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.thatcube.mozz"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.brando.mozz"
        minSdk = 28
        targetSdk = 37
        versionCode = mozzVersionCode
        versionName = mozzVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    androidResources {
        // The analyzer's weights are read as a file, not as a stream, and an
        // asset only has a file descriptor when it is stored uncompressed.
        // They are half-precision floats, so compression buys almost nothing
        // and costs a decompression pass on first run.
        noCompress += "bin"
    }


    packaging {
        jniLibs {
            // Do not strip the audio DSP.
            //
            // The library is built 16 KB page aligned, which Android 15 and
            // later require, and AGP's strip step rewrites its program headers
            // back to 4 KB — verified by reading the alignment out of the
            // staged file and again out of the APK. A Pixel says so in a dialog
            // naming the library; a user's phone would simply fail to load it
            // and lose the equaliser with no explanation.
            //
            // Cargo already strips symbols on the way out, so nothing is being
            // kept here that AGP would have removed.
            keepDebugSymbols += "**/libmozz_audio_android.so"
        }
    }

    // Release signing, supplied by the environment rather than committed.
    //
    // An APK Android will install has to be signed, and an unsigned
    // `app-release-unsigned.apk` is not a release — the installer rejects it
    // with no useful message. The keystore and its passwords are credentials:
    // they live in the maintainer's hands and in CI secrets, never in the repo.
    //
    // Deliberately absent-tolerant. A contributor without the keystore can still
    // run `assembleRelease` to check that R8 does not break anything, which is
    // the thing worth checking; they get an unsigned APK and that is correct.
    // The release workflow asserts the signature separately, so a missing secret
    // fails the release rather than quietly publishing something uninstallable.
    //
    // To create one (maintainer, once — keep the file and the passwords safe;
    // losing them means no existing install can ever be updated):
    //
    //   tools/make-release-keystore.sh
    //
    // Then set MOZZ_KEYSTORE (path) and MOZZ_KEYSTORE_PASSWORD. MOZZ_KEY_ALIAS
    // and MOZZ_KEY_PASSWORD are optional and default to `mozz` and the store
    // password.
    val keystoreFile = System.getenv("MOZZ_KEYSTORE")?.takeIf { it.isNotBlank() }?.let(::file)

    signingConfigs {
        if (keystoreFile != null && keystoreFile.exists()) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("MOZZ_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("MOZZ_KEY_ALIAS") ?: "mozz"
                // The key password falls back to the store's.
                //
                // A keystore protects the file; a key password protects one
                // entry inside it, so a build server can be given one key out of
                // several. Mozz has one key, and keytool has defaulted to PKCS12
                // since JDK 9, where the two have to match anyway — so requiring
                // a separate secret for it was two places to set one value, and
                // a mismatch would fail the release for no reason a reader could
                // see. Still honoured when set, for a keystore that does differ.
                keyPassword = System.getenv("MOZZ_KEY_PASSWORD")
                    ?.takeIf { it.isNotBlank() }
                    ?: System.getenv("MOZZ_KEYSTORE_PASSWORD")
                // Both asked for; AGP emits only what minSdk needs.
                //
                // Worth knowing before reading an `apksigner verify` report and
                // thinking something is wrong: AGP prunes signature schemes that
                // are redundant for the declared minSdk, whatever is requested
                // here. At minSdk 28 that means v1 (JAR signing, only needed
                // below API 24) is dropped, and so is v2 once v3 is on — the
                // verifier then prints `v2: false, v3: true`, which is a correct
                // and complete signature for every Android this app supports.
                //
                // v3 is on for the proof-of-rotation record it carries. It
                // changes nothing today, and it is the only mechanism by which
                // Mozz could ever move to a different signing key without every
                // installed copy becoming un-updatable. It cannot be added
                // retroactively to builds already shipped, so the time to turn
                // it on is the first release.
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // The Swift runtime payload is large and unstripped. Splitting by ABI keeps
    // a phone from carrying the emulator's x86_64 copy of all of it.
    splits {
        abi {
            isEnable = true
            reset()
            include(*androidAbis.toTypedArray())
            isUniversalApk = false
        }
    }

    buildFeatures {
        compose = true
        // Needed only to tell a debug build from a release one at runtime, which
        // gates the image logger — it prints artwork URLs, and those carry the
        // server token.
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    sourceSets {
    }
}

dependencies {
    implementation(project(":core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.adaptive)
    implementation(libs.androidx.adaptive.layout)
    implementation(libs.androidx.adaptive.navigation)

    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.session)

    debugImplementation(libs.androidx.compose.ui.tooling)
    androidTestImplementation(libs.androidx.test.junit)
}
