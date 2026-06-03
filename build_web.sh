#!/usr/bin/env bash
set -e

FLUTTER_VERSION="${FLUTTER_VERSION:-3.24.5}"
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_TAR}"

echo ">>> Installing Flutter ${FLUTTER_VERSION}..."
curl -fsSL "$FLUTTER_URL" -o flutter.tar.xz
mkdir -p flutter_sdk
tar xf flutter.tar.xz -C flutter_sdk --strip-components=1
export PATH="$PATH:$(pwd)/flutter_sdk/bin"

echo ">>> Flutter version:"
flutter --version --no-version-check

echo ">>> Getting dependencies..."
flutter pub get

echo ">>> Building Flutter web (release)..."
flutter build web --release

echo ">>> Build complete. Output in build/web/"
