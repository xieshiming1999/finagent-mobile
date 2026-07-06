#!/bin/bash
# Run FinAgent on a connected Android device via USB + ADB
# Usage: ./run_android_device.sh

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

if [ -z "$ANDROID_HOME" ]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
fi
if [ -z "$ANDROID_SDK_ROOT" ]; then
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
fi
if [ -d "$ANDROID_HOME/platform-tools" ]; then
    export PATH="$ANDROID_HOME/platform-tools:$PATH"
fi

if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found. Install Android SDK Platform-Tools or add it to PATH."
    echo "Expected: $ANDROID_HOME/platform-tools/adb"
    exit 1
fi

# Check for connected device
DEVICE=$(adb devices | grep -w "device" | head -1 | awk '{print $1}')
if [ -z "$DEVICE" ]; then
    echo "No Android device found. Please connect via USB and enable USB debugging."
    exit 1
fi

echo "Found device: $DEVICE"

MIN_DATA_FREE_KB=${MIN_DATA_FREE_KB:-6291456} # 6 GiB
DATA_FREE_KB=$(adb -s "$DEVICE" shell df -k /data 2>/dev/null | awk 'NR==2 {print $4}' | tr -d '\r')
if [ -n "$DATA_FREE_KB" ] && [ "$DATA_FREE_KB" -lt "$MIN_DATA_FREE_KB" ]; then
    FREE_GB=$(awk "BEGIN {printf \"%.1f\", $DATA_FREE_KB / 1048576}")
    NEED_GB=$(awk "BEGIN {printf \"%.1f\", $MIN_DATA_FREE_KB / 1048576}")
    echo "Device /data has only ${FREE_GB} GiB free; need at least ${NEED_GB} GiB for a safe debug install."
    echo "Aborting before flutter run. Flutter may uninstall the existing app after INSTALL_FAILED_INSUFFICIENT_STORAGE, which deletes FinAgent settings."
    echo "Free device storage or rerun with MIN_DATA_FREE_KB=<kilobytes> if you intentionally want to bypass this guard."
    exit 1
fi

# Forward port: device localhost:3033 → Mac localhost:3033
echo "Setting up port forwarding (3033)..."
adb -s "$DEVICE" reverse tcp:3033 tcp:3033

echo "Starting FinAgent app (system noise filtered)..."
cd "$(dirname "$0")"
flutter run -d "$DEVICE" 2>&1 | grep -v \
    -e "hwschromium" \
    -e "OpenGLRenderer" \
    -e "gpu complete is not signaled" \
    -e "ShouldDoAdaptiveRelayout" \
    -e "fraud_web_report" \
    -e "HWBFCACHE" \
    -e "Compiler allocated.*to compile" \
    -e "FlutterJNI" \
    -e "viewport metrics" \
    -e "HwDragEnhancement" \
    -e "WebViewDragEnhancement" \
    -e "AudioManager" \
    -e "hwbr_engine" \
    -e "HwViewRootImpl" \
    -e "removeInvalidNode" \
    -e "MessageLoop for current thread" \
    -e "MicroMsg.Flutter" \
    -e "WxaLiteApp" \
    -e "LiteApp.Wxa" \
    -e "DartVM.*RegisterMM" \
    -e "wxa_lite_app" \
    -e "Catcher |" \
    -e "VideoCapabilities" \
    -e "Unsupported mime" \
    -e "Unsupported profile" \
    -e "Unrecognized profile" \
    -e "WindowManager.*trimMemory" \
    -e "stylus.*touchlistener" \
    -e "Hwaps" \
    -e "HwAps" \
    -e "HiTouch" \
    -e "Settings.*device_provisioned" \
    -e "LifecycleTransaction" \
    -e "TopResumedActivityChangeItem" \
    -e "InsetsSourceConsumer" \
    -e "SurfaceView" \
    -e "nagent.finagen.*xdraw" \
    -e "InputMethodManager" \
    -e "InsetsController" \
    -e "SceneHelper" \
    -e "RmeSchedManager" \
    -e "setNextServedView\|setServedView" \
    -e "BufferQueueCore" \
    -e "Gralloc" \
    -e "AwareBitmapCacher" \
    -e "ProfileInstaller" \
    -e "ActivityThread.*Won't deliver" \
    -e "DecorView.*updateColor" \
    -e "HwMediaViewLayoutChange" \
    -e "ImeFocusController" \
    -e "LoadedApk.*sharedLibraries" \
    -e "SysUtils" \
    -e "HwApkAssets" \
    -e "CompatibilityChangeReporter" \
    -e "InputManager.*registerInput" \
    -e "nagent.finagen.*package\[" \
    -e "setLowResolutionInfo" \
    -e "ScopedThresholdTiming" \
    -e "DecodeWeakGlobal" \
    -e "Accessing hidden method" \
    -e "AssistStructure"
