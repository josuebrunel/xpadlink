#!/usr/bin/env bash
# Generates the Flutter Android project in ./xpadlink_app and drops our code into it.
set -euo pipefail
cd "$(dirname "$0")"

flutter create --org com.example --project-name xpadlink --platforms android xpadlink_app
rm -f xpadlink_app/test/widget_test.dart  # references the default MyApp
cp lib/*.dart xpadlink_app/lib/
cp kotlin/*.kt xpadlink_app/android/app/src/main/kotlin/com/example/xpadlink/

# Release builds need the INTERNET permission (flutter create only adds it for debug).
manifest=xpadlink_app/android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$manifest" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"

# Lock to landscape from the first frame, ignoring the system auto-rotate setting.
grep -q 'android:screenOrientation' "$manifest" || \
  sed -i 's#android:name=".MainActivity"#android:name=".MainActivity"\n            android:screenOrientation="sensorLandscape"#' "$manifest"

grep -q 'android.permission.VIBRATE' "$manifest" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.VIBRATE"/>\n    <application#' "$manifest"

# Bluetooth: BLUETOOTH_CONNECT on Android 12+, the old pair on older versions.
grep -q 'android.permission.BLUETOOTH_CONNECT' "$manifest" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>\n    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>\n    <application#' "$manifest"

# Bundled fonts and the logo (no network needed on a phone that only has Bluetooth).
mkdir -p xpadlink_app/assets/fonts
cp assets/fonts/*.ttf xpadlink_app/assets/fonts/
grep -q 'family: ChakraPetch' xpadlink_app/pubspec.yaml || python3 - xpadlink_app/pubspec.yaml <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
decl = """  uses-material-design: true

  assets:
    - assets/logo.png

  fonts:
    - family: ChakraPetch
      fonts:
        - asset: assets/fonts/ChakraPetch-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/ChakraPetch-Bold.ttf
          weight: 700
    - family: Barlow
      fonts:
        - asset: assets/fonts/Barlow-Regular.ttf
        - asset: assets/fonts/Barlow-Medium.ttf
          weight: 500
        - asset: assets/fonts/Barlow-SemiBold.ttf
          weight: 600
    - family: JetBrainsMono
      fonts:
        - asset: assets/fonts/JetBrainsMono-Regular.ttf
        - asset: assets/fonts/JetBrainsMono-Medium.ttf
          weight: 500
        - asset: assets/fonts/JetBrainsMono-Bold.ttf
          weight: 700
"""
assert "  uses-material-design: true\n" in s
open(p, "w").write(s.replace("  uses-material-design: true\n", decl, 1))
PY

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
