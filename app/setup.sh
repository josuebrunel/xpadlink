#!/usr/bin/env bash
# Generates the Flutter Android project in ./xpadlink_app and drops our code into it.
set -euo pipefail
cd "$(dirname "$0")"

flutter create --org com.example --project-name xpadlink --platforms android xpadlink_app
cp lib/*.dart xpadlink_app/lib/
cp kotlin/MainActivity.kt xpadlink_app/android/app/src/main/kotlin/com/example/xpadlink/MainActivity.kt

# Release builds need the INTERNET permission (flutter create only adds it for debug).
manifest=xpadlink_app/android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$manifest" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$manifest"

(cd xpadlink_app && flutter pub add shared_preferences)
echo "Done. Run: cd xpadlink_app && flutter run   (phone connected with USB debugging)"
