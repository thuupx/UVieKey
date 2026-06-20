#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_OWNER="thuupx"
REPO_NAME="uvie-rs"
VERSION_FILE="$PROJECT_ROOT/uvie-rs-version"

if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    echo "Error: version file not found: $VERSION_FILE"
    exit 1
fi

if [ -z "$VERSION" ]; then
    echo "Error: uvie-rs version is empty"
    exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}/uvie-macos-universal.tar.gz"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"
TMP_DIR=$(mktemp -d)

echo "Fetching uvie-rs v${VERSION}..."
echo "URL: ${DOWNLOAD_URL}"

curl -fsSL -L "$DOWNLOAD_URL" -o "$TMP_DIR/uvie-macos-universal.tar.gz"

echo "Extracting to ${OUTPUT_DIR}..."
mkdir -p "$OUTPUT_DIR"
tar xzf "$TMP_DIR/uvie-macos-universal.tar.gz" -C "$TMP_DIR"
cp "$TMP_DIR/uvie/libuvie.a" "$OUTPUT_DIR/libuvie.a"
cp "$TMP_DIR/uvie/uvie.h" "$OUTPUT_DIR/uvie.h"

rm -rf "$TMP_DIR"

echo "uvie-rs v${VERSION} ready at ${OUTPUT_DIR}/libuvie.a"
