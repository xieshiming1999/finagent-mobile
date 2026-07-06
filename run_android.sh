#!/bin/bash
# Run FinAgent on Android emulator
# Usage: ./run_android.sh

ANDROID_SDK="$HOME/Library/Android/sdk"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

AVD_NAME="pixel7_api34"
IMAGE="system-images;android-34;google_apis;arm64-v8a"

# Check if emulator is already running
if pgrep -f "emulator.*$AVD_NAME" > /dev/null; then
    echo "Emulator already running."
else
    # Create AVD if it doesn't exist
    if ! "$ANDROID_SDK/emulator/emulator" -list-avds | grep -q "$AVD_NAME"; then
        echo "Creating AVD '$AVD_NAME'..."
        "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" "$IMAGE"
        "$ANDROID_SDK/cmdline-tools/latest/bin/avdmanager" create avd \
            -n "$AVD_NAME" -k "$IMAGE" -d pixel_7 --force
    fi

    echo "Starting emulator..."
    "$ANDROID_SDK/emulator/emulator" -avd "$AVD_NAME" &

    # Wait for emulator to boot
    echo "Waiting for emulator to boot..."
    adb wait-for-device
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        sleep 2
    done
    echo "Emulator ready."
fi

# Set up reverse port forwarding so emulator can reach host server
adb reverse tcp:3033 tcp:3033
echo "Port 3033 reverse forwarded."

# Run Flutter
echo "Starting FinAgent app..."
cd "$(dirname "$0")"
flutter run
