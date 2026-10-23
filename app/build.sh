#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/../dist"
BUILD="$ROOT/build"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
BUILD_TOOLS="${BUILD_TOOLS:-$SDK/build-tools/35.0.0}"
PLATFORM="${PLATFORM:-$SDK/platforms/android-34/android.jar}"

AAPT2="$BUILD_TOOLS/aapt2"
D8="$BUILD_TOOLS/d8"
ZIPALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"

APP_NAME="thomkhali"
PACKAGE="com.thomkhali.guns"
VERSION_NAME="1.0.0"
VERSION_CODE="1"

for tool in "$AAPT2" "$D8" "$ZIPALIGN" "$APKSIGNER" "$PLATFORM"; do
    if [[ ! -e "$tool" ]]; then
        echo "Missing build tool: $tool" >&2
        exit 1
    fi
done

if [[ ! -f "$ROOT/tools/icon-source.png" ]]; then
    echo "Missing icon source." >&2
    exit 1
fi

if [[ ! -f "$ROOT/res/mipmap-xxxhdpi/ic_launcher.png" ]]; then
    python3 "$ROOT/tools/make_icons.py"
fi

SIGN_DIR="$DIST/signing"
KEYSTORE="$SIGN_DIR/thomkhali-release.jks"
PROPS="$SIGN_DIR/keystore.properties"

if [[ ! -f "$KEYSTORE" ]]; then
    mkdir -p "$SIGN_DIR"
    chmod 700 "$SIGN_DIR"
    PASS="$(openssl rand -hex 24)"
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -alias "$APP_NAME" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "$PASS" \
        -keypass "$PASS" \
        -dname "CN=$APP_NAME, OU=Mobile, O=$APP_NAME, C=BR" \
        >/dev/null
    {
        echo "STORE_PASS=$PASS"
        echo "KEY_PASS=$PASS"
        echo "ALIAS=$APP_NAME"
    } > "$PROPS"
    chmod 600 "$KEYSTORE" "$PROPS"
    echo "Created new signing key: $KEYSTORE"
fi

# shellcheck disable=SC1090
source "$PROPS"

rm -rf "$BUILD"
mkdir -p "$BUILD/flat" "$BUILD/gen" "$BUILD/classes" "$BUILD/dex" "$DIST"

echo "[1/6] Compiling resources"
"$AAPT2" compile --dir "$ROOT/res" -o "$BUILD/flat/resources.zip"

echo "[2/6] Linking resources"
"$AAPT2" link \
    -o "$BUILD/base-unsigned.apk" \
    -I "$PLATFORM" \
    --manifest "$ROOT/AndroidManifest.xml" \
    --java "$BUILD/gen" \
    --min-sdk-version 24 \
    --target-sdk-version 34 \
    --version-code "$VERSION_CODE" \
    --version-name "$VERSION_NAME" \
    -R "$BUILD/flat/resources.zip" \
    --auto-add-overlay

echo "[3/6] Compiling Java"
mapfile -t JAVA_SOURCES < <(find "$ROOT/src" "$BUILD/gen" -name '*.java' -print)
javac \
    -source 8 \
    -target 8 \
    -bootclasspath "$PLATFORM" \
    -classpath "$PLATFORM" \
    -encoding UTF-8 \
    -d "$BUILD/classes" \
    "${JAVA_SOURCES[@]}"

echo "[4/6] Building dex"
mapfile -t CLASS_FILES < <(find "$BUILD/classes" -name '*.class' -print)
"$D8" --release --min-api 24 --lib "$PLATFORM" --output "$BUILD/dex" "${CLASS_FILES[@]}"

echo "[5/6] Packaging and aligning"
cp "$BUILD/base-unsigned.apk" "$BUILD/with-dex.apk"
(
    cd "$BUILD/dex"
    zip -q -X "$BUILD/with-dex.apk" classes.dex
)
"$ZIPALIGN" -f -p 4 "$BUILD/with-dex.apk" "$BUILD/aligned.apk"

echo "[6/6] Signing"
OUTPUT="$DIST/$APP_NAME-$VERSION_NAME.apk"
"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-key-alias "$ALIAS" \
    --ks-pass "pass:$STORE_PASS" \
    --key-pass "pass:$KEY_PASS" \
    --min-sdk-version 24 \
    --out "$OUTPUT" \
    "$BUILD/aligned.apk"

"$APKSIGNER" verify --verbose "$OUTPUT" >/dev/null

echo
echo "Package: $PACKAGE"
echo "APK:     $OUTPUT"
echo "Size:    $(du -h "$OUTPUT" | cut -f1)"
