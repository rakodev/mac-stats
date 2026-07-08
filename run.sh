#!/bin/bash

set -euo pipefail

# Kill any existing MacStats processes
pkill -f MacStats 2>/dev/null || true

# Build the app if needed
make dev

# Get the latest Debug build path dynamically
BUILD_PATH=$(
    find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/Debug/MacStats.app" -type d -print0 2>/dev/null |
    while IFS= read -r -d '' app; do
        printf '%s\t%s\n' "$(stat -f '%m' "$app")" "$app"
    done |
    sort -nr |
    head -n 1 |
    cut -f2-
)

if [ -z "$BUILD_PATH" ]; then
    echo "❌ MacStats.app not found in DerivedData"
    echo "Please run 'make dev' first to build the app"
    exit 1
fi

echo "🚀 Starting MacStats from: $BUILD_PATH"

# Open the app
open "$BUILD_PATH"

echo "✅ MacStats started! Check your menu bar for the enabled stats."
echo "If you don't see it immediately, it may take a few seconds to appear."