#!/bin/bash
# Run FinAgent on macOS
# Usage: ./run_macos.sh

cd "$(dirname "$0")"

# Get dependencies if needed
flutter pub get 2>/dev/null
flutter run -d macos
