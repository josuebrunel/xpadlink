#!/usr/bin/env bash
# Generates the Flutter Android project in ./xpadlink_app and drops our code into it.
set -euo pipefail
cd "$(dirname "$0")"

flutter create --org com.example --project-name xpadlink --platforms android xpadlink_app
rm -f xpadlink_app/test/widget_test.dart  # references the default MyApp
cp lib/*.dart xpadlink_app/lib/
cp kotlin/MainActivity.kt xpadlink_app/android/app/src/main/kotlin/com/example/xpadlink/MainActivity.kt

# Release builds need the INTERNET permission (flutter create only adds it for debug).
manifest=xpadlink_app/android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$manifest" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"

# Lock to landscape from the first frame, ignoring the system auto-rotate setting.
grep -q 'android:screenOrientation' "$manifest" || \
  sed -i 's#android:name=".MainActivity"#android:name=".MainActivity"\n            android:screenOrientation="sensorLandscape"#' "$manifest"

# Release signing: use android/key.properties when present (CI writes it), else the debug key.
gradle=xpadlink_app/android/app/build.gradle.kts
grep -q keystoreProps "$gradle" || python3 - "$gradle" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = "import java.util.Properties\n\n" + s
s = s.replace("android {", """val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {""", 1)
s = s.replace("    buildTypes {", """    signingConfigs {
        create("release") {
            if (keystoreProps.containsKey("storeFile")) {
                storeFile = rootProject.file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
    }

    buildTypes {""", 1)
s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName(if (keystoreProps.containsKey("storeFile")) "release" else "debug")', 1)
open(p, "w").write(s)
PY

# Launcher icons from the logo in assets/.
mkdir -p xpadlink_app/assets
cp assets/logo*.png xpadlink_app/assets/
cp flutter_launcher_icons.yaml xpadlink_app/

(cd xpadlink_app && flutter pub add shared_preferences && \
  flutter pub add --dev flutter_launcher_icons && \
  dart run flutter_launcher_icons)
echo "Done. Run: cd xpadlink_app && flutter run   (phone connected with USB debugging)"
