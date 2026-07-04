#!/bin/bash
# Fetch and extract Sparkle.framework for building UVieKey with in-app updates.
# Downloads the official Sparkle 2.x release from GitHub.
set -euo pipefail

SPARKLE_VERSION="2.9.4"
FRAMEWORKS_DIR="$(dirname "$0")/../Frameworks"
TAR_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

if [ -d "${FRAMEWORKS_DIR}/Sparkle.framework" ]; then
    echo "[fetch-sparkle] Sparkle.framework already present, skipping."
    exit 0
fi

echo "[fetch-sparkle] Downloading Sparkle ${SPARKLE_VERSION}..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -sL "$TAR_URL" -o "$TMP_DIR/Sparkle.tar.xz"
tar xf "$TMP_DIR/Sparkle.tar.xz" -C "$TMP_DIR"

cp -R "$TMP_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/"
echo "[fetch-sparkle] Sparkle.framework installed to ${FRAMEWORKS_DIR}/Sparkle.framework"

# Also extract the sign_update tool for CI use
mkdir -p "$FRAMEWORKS_DIR/sparkle-bin"
cp "$TMP_DIR/bin/sign_update" "$FRAMEWORKS_DIR/sparkle-bin/"
cp "$TMP_DIR/bin/generate_appcast" "$FRAMEWORKS_DIR/sparkle-bin/"
echo "[fetch-sparkle] Sparkle tools installed to ${FRAMEWORKS_DIR}/sparkle-bin/"
