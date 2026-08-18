#!/usr/bin/env bash
#
# deploy.sh - Build and deploy a Vela Quick App RPK to a Xiaomi wearable
#
# Deploys via the hidden "Third App Support" debug page in Mi Fitness.
# Requires: ADB, Android SDK (javac + d8), phone paired with band.
#
# Usage:
#   ./deploy.sh --project <dir> [options]
#
# Options:
#   --project <dir>       Path to the Vela JS project (required)
#   --serial <serial>     Phone ADB serial (default: auto-detect)
#   --no-build            Skip building, deploy existing RPK
#   --uninstall           Uninstall old version before installing
#   -h, --help            Show this help
#
# Environment variables:
#   PHONE_SERIAL          Phone ADB serial (overridden by --serial)
#   ANDROID_HOME          Android SDK path (also accepts ANDROID_SDK_ROOT)
#   PICKER_WAIT_SECONDS   Seconds to wait for RPK selection (default: 180)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Defaults ---
PHONE_SERIAL="${PHONE_SERIAL:-}"
PROJECT_DIR=""
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
DO_BUILD=true
DO_UNINSTALL=false
PICKER_WAIT_SECONDS="${PICKER_WAIT_SECONDS:-180}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)    PROJECT_DIR="$2"; shift 2 ;;
        --serial)     PHONE_SERIAL="$2"; shift 2 ;;
        --no-build)   DO_BUILD=false; shift ;;
        --uninstall)  DO_UNINSTALL=true; shift ;;
        -h|--help)
            sed -n '2,/^$/{ s/^# \?//; p }' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: --project <dir> is required"
    echo "Run with --help for usage"
    exit 1
fi

# --- Locate the Android SDK when the caller did not set an environment variable ---
if [ -z "$ANDROID_HOME" ]; then
    HOME_DIR="${HOME:?HOME is required to locate the Android SDK}"
    for CANDIDATE in "$HOME_DIR/Android/Sdk" "$HOME_DIR/Library/Android/sdk"; do
        if [ -d "$CANDIDATE" ]; then
            ANDROID_HOME="$CANDIDATE"
            break
        fi
    done
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# --- Read package name from manifest.json ---
MANIFEST="$PROJECT_DIR/src/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: No manifest.json found at $MANIFEST"
    exit 1
fi
PKG_NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$MANIFEST')).package)")
RPK_FILENAME="$(echo "$PKG_NAME" | tr '.' '_').rpk"

# --- Auto-detect phone serial ---
if [ -z "$PHONE_SERIAL" ]; then
    # Try USB devices first, then wireless
    PHONE_SERIAL=$(adb devices | grep -v emulator | grep -E 'device$' | head -1 | awk '{print $1}')
    if [ -z "$PHONE_SERIAL" ]; then
        echo "ERROR: No phone found via ADB. Connect via USB or wireless debugging."
        echo "  USB: plug in phone with USB debugging enabled"
        echo "  Wireless: adb pair <ip:port> <code>, then adb connect <ip:port>"
        exit 1
    fi
fi
ADB="adb -s ${PHONE_SERIAL}"

# --- Auto-detect Android SDK tools ---
if [ -z "$ANDROID_HOME" ]; then
    echo "ERROR: Android SDK path not found. Set ANDROID_HOME or ANDROID_SDK_ROOT."
    exit 1
fi
if [ ! -d "$ANDROID_HOME" ]; then
    echo "ERROR: Android SDK not found at $ANDROID_HOME"
    echo "Set ANDROID_HOME to your SDK path"
    exit 1
fi

# Find latest platform
PLATFORM=$(ls -d "$ANDROID_HOME"/platforms/android-* 2>/dev/null | sort -V | tail -1)/android.jar
if [ ! -f "$PLATFORM" ]; then
    echo "ERROR: No Android platform found in $ANDROID_HOME/platforms/"
    exit 1
fi

# Find latest build-tools
BUILD_TOOLS=$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -1)
if [ ! -d "$BUILD_TOOLS" ]; then
    echo "ERROR: No build-tools found in $ANDROID_HOME/build-tools/"
    exit 1
fi

DEVICE_RPK="/sdcard/Xiaomi-band/$RPK_FILENAME"
LAUNCH_DEX="/data/local/tmp/launch.dex"
LAUNCH_JAVA="/tmp/LaunchFragment.java"

# --- Verify prerequisites ---
echo "==> Phone: $PHONE_SERIAL"
echo "==> Package: $PKG_NAME"
if ! $ADB get-state &>/dev/null; then
    echo "ERROR: Device $PHONE_SERIAL not reachable via ADB"
    exit 1
fi

# --- Step 1: Build ---
if [ "$DO_BUILD" = true ]; then
    echo "==> Building..."
    (cd "$PROJECT_DIR" && npm run build 2>&1 | tail -2)
else
    echo "==> Skipping build (--no-build)"
fi

# Find the RPK
RPK_FILE=$(find "$PROJECT_DIR/dist" -name "*.rpk" -type f | sort -r | head -1)
if [ -z "$RPK_FILE" ]; then
    echo "ERROR: No .rpk file found in $PROJECT_DIR/dist/"
    exit 1
fi
echo "==> RPK: $RPK_FILE"

# --- Step 2: Ensure launch.dex exists ---
if ! $ADB shell "test -f $LAUNCH_DEX" 2>/dev/null; then
    echo "==> Building launcher dex..."
    if [ ! -f "$LAUNCH_JAVA" ]; then
        cat > "$LAUNCH_JAVA" << 'JAVA'
import android.content.Intent;
import android.os.Looper;
import android.os.Parcelable;

public class LaunchFragment {
    public static void main(String[] args) {
        try {
            Looper.prepareMainLooper();
            String apkPath = args[0];
            dalvik.system.PathClassLoader cl = new dalvik.system.PathClassLoader(apkPath, ClassLoader.getSystemClassLoader());
            Class<?> builderClass = cl.loadClass("com.xiaomi.fitness.baseui.common.FragmentParams$b");
            Object builder = builderClass.newInstance();
            Class<?> fragmentClass = cl.loadClass("com.xiaomi.xms.wearable.ui.debug.ThirdAppDebugFragment");
            java.lang.reflect.Method setClass = builderClass.getMethod("e", Class.class);
            setClass.invoke(builder, fragmentClass);
            java.lang.reflect.Method build = builderClass.getMethod("b");
            Object fp = build.invoke(builder);
            Intent intent = new Intent();
            intent.setClassName("com.xiaomi.wearable", "com.xiaomi.fitness.baseui.common.CommonBaseActivity");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.putExtra("fragment_param", (Parcelable) fp);
            Class<?> amClass = Class.forName("android.app.ActivityManager");
            java.lang.reflect.Method getService = amClass.getDeclaredMethod("getService");
            getService.setAccessible(true);
            Object am = getService.invoke(null);
            for (java.lang.reflect.Method m : am.getClass().getMethods()) {
                if (m.getName().equals("startActivity") && m.getParameterTypes().length == 10) {
                    Object[] callArgs = new Object[10];
                    Class<?>[] params = m.getParameterTypes();
                    for (int i = 0; i < 10; i++) {
                        if (params[i] == int.class) callArgs[i] = 0;
                        else if (params[i] == Intent.class) callArgs[i] = intent;
                        else if (params[i] == String.class && i == 1) callArgs[i] = "com.android.shell";
                        else callArgs[i] = null;
                    }
                    m.invoke(am, callArgs);
                    System.out.println("SUCCESS");
                    return;
                }
            }
            System.out.println("FAILED: no matching startActivity method");
        } catch (Throwable e) {
            System.err.println("ERROR: " + e);
            e.printStackTrace();
        }
    }
}
JAVA
    fi
    javac -source 8 -target 8 -bootclasspath "$PLATFORM" "$LAUNCH_JAVA" -d /tmp/launch_classes 2>/dev/null
    mkdir -p /tmp/launch_dex
    "$BUILD_TOOLS/d8" /tmp/launch_classes/LaunchFragment.class --output /tmp/launch_dex/ 2>/dev/null
    $ADB push /tmp/launch_dex/classes.dex "$LAUNCH_DEX" 2>/dev/null
    echo "    Launcher dex ready"
fi

# --- Step 3: Push RPK ---
echo "==> Pushing RPK to device..."
$ADB shell mkdir -p /sdcard/Xiaomi-band 2>/dev/null || true
$ADB push "$RPK_FILE" "$DEVICE_RPK"

# --- Step 4: Get APK path and launch debug page ---
APK_PATH=$($ADB shell pm path com.xiaomi.wearable | head -1 | sed 's/package://' | tr -d '\r')
if [ -z "$APK_PATH" ]; then
    echo "ERROR: Mi Fitness (com.xiaomi.wearable) not found on phone"
    exit 1
fi
echo "==> Launching Third App Support debug page..."
RESULT=$($ADB shell "CLASSPATH=$LAUNCH_DEX app_process / LaunchFragment $APK_PATH" 2>&1)
if ! echo "$RESULT" | grep -q "SUCCESS"; then
    echo "ERROR: Failed to launch debug page: $RESULT"
    exit 1
fi
echo "    Debug page launched"

# --- Step 5: Automate UI interaction ---
sleep 4

UI_REMOTE="/sdcard/ui_tmp.xml"
UI_LOCAL="/tmp/xiaomi_band_ui_${PHONE_SERIAL//[^[:alnum:]]/_}.xml"

dump_ui() {
    $ADB shell uiautomator dump "$UI_REMOTE" >/dev/null 2>&1 || return 1
    $ADB exec-out cat "$UI_REMOTE" > "$UI_LOCAL" 2>/dev/null
}

ui_value_by_id() {
    local RESOURCE_ID="$1"
    local VALUE_NAME="$2"
    python3 - "$UI_LOCAL" "$RESOURCE_ID" "$VALUE_NAME" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, resource_id, value_name = sys.argv[1:]
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, OSError):
    raise SystemExit(0)

for node in root.iter("node"):
    if node.attrib.get("resource-id") == resource_id:
        print(node.attrib.get(value_name, ""))
        break
PY
}

ui_center_by_id() {
    local RESOURCE_ID="$1"
    local BOUNDS
    BOUNDS=$(ui_value_by_id "$RESOURCE_ID" bounds)
    python3 - "$BOUNDS" <<'PY'
import re
import sys

m = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", sys.argv[1])
if m:
    x1, y1, x2, y2 = map(int, m.groups())
    print((x1 + x2) // 2, (y1 + y2) // 2)
PY
}

wait_for_id() {
    local RESOURCE_ID="$1"
    local ATTEMPTS="${2:-10}"
    local I
    for ((I=0; I<ATTEMPTS; I++)); do
        if dump_ui && [ -n "$(ui_value_by_id "$RESOURCE_ID" bounds)" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

tap_id() {
    local RESOURCE_ID="$1"
    local COORDS
    dump_ui || return 1
    COORDS=$(ui_center_by_id "$RESOURCE_ID")
    [ -n "$COORDS" ] || return 1
    $ADB shell input tap $COORDS
}

enter_package_name() {
    echo "==> Entering package name..."
    if ! wait_for_id "com.xiaomi.wearable:id/inputPackageName" 10; then
        echo "ERROR: Third App Support page is not visible."
        echo "Close the current Mi Fitness detail page and run the command again."
        exit 1
    fi
    tap_id "com.xiaomi.wearable:id/inputPackageName"

    if ! wait_for_id "com.xiaomi.wearable:id/pkgNameView" 10; then
        echo "ERROR: Package-name dialog did not open."
        exit 1
    fi
    tap_id "com.xiaomi.wearable:id/pkgNameView"
    $ADB shell input text "$PKG_NAME"
    sleep 1

    dump_ui
    local ENTERED
    ENTERED=$(ui_value_by_id "com.xiaomi.wearable:id/pkgNameView" text)
    if [ "$ENTERED" != "$PKG_NAME" ]; then
        echo "ERROR: Package name was entered incorrectly."
        echo "  Expected: $PKG_NAME"
        echo "  Actual:   $ENTERED"
        exit 1
    fi

    tap_id "android:id/button1"
    sleep 2
    dump_ui
    local CONFIRMED
    CONFIRMED=$(ui_value_by_id "com.xiaomi.wearable:id/showPackageName" text)
    if [ "$CONFIRMED" != "$PKG_NAME" ]; then
        echo "ERROR: Mi Fitness did not confirm the package name."
        exit 1
    fi
    echo "    Package name confirmed"
}

enter_package_name

if [ "$DO_UNINSTALL" = true ]; then
    echo "==> Uninstalling old version..."
    if ! tap_id "com.xiaomi.wearable:id/unInstallThirdApp"; then
        echo "ERROR: Uninstall button not found"
        exit 1
    fi
    sleep 5
fi

echo "==> Tapping 'install third app'..."
if ! tap_id "com.xiaomi.wearable:id/installThirdApp"; then
    echo "ERROR: Install button not found"
    exit 1
fi
sleep 3

ACTIVITIES=$($ADB shell dumpsys activity activities)
if [[ "$ACTIVITIES" != *com.google.android.documentsui* ]]; then
    echo "ERROR: Android file picker did not open."
    exit 1
fi

echo ""
echo "==> File picker opened successfully."
echo "    Select Xiaomi-band/$RPK_FILENAME on the phone."
echo ""
echo "    Waiting up to ${PICKER_WAIT_SECONDS}s for the selection..."

ELAPSED=0
while [ "$ELAPSED" -lt "$PICKER_WAIT_SECONDS" ]; do
    ACTIVITIES=$($ADB shell dumpsys activity activities)
    if [[ "$ACTIVITIES" != *topResumedActivity=*com.google.android.documentsui* ]]; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$ELAPSED" -ge "$PICKER_WAIT_SECONDS" ]; then
    echo "WARN: Timed out waiting for RPK selection."
    exit 2
fi

echo "==> File returned to Mi Fitness; waiting for band result..."
# Give onActivityResult/prepareInstall time to read the content URI and update
# the result label. On HyperOS this took about three seconds in testing.
sleep 5
STATUS=""
for ((I=0; I<30; I++)); do
    if dump_ui; then
        STATUS=$(ui_value_by_id "com.xiaomi.wearable:id/thirdappstatus" text)
        [ -n "$STATUS" ] && break
    fi
    sleep 1
done

case "$STATUS" in
    "发送文件成功")
        echo "SUCCESS: Mi Fitness reports 'file sent successfully'."
        ;;
    "")
        echo "WARN: Mi Fitness returned without a visible final status."
        echo "Check the band app list and run filtered logcat if needed."
        exit 3
        ;;
    *)
        echo "RESULT: $STATUS"
        echo "The band may be disconnected or Mi Fitness may have rejected the file."
        exit 4
        ;;
esac
