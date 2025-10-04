#!/bin/bash

# Kill any existing MacStats processes
pkill -f MacStats 2>/dev/null || true

# Build the app if needed
make dev

# Get the latest build path dynamically
BUILD_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "MacStats.app" -type d 2>/dev/null | head -1)

if [ -z "$BUILD_PATH" ]; then
    echo "❌ MacStats.app not found in DerivedData"
    echo "Please run 'make dev' first to build the app"
    exit 1
fi

echo "🚀 Starting MacStats from: $BUILD_PATH"

# Open the app
open "$BUILD_PATH"

echo "✅ MacStats started! Check your menu bar for the CPU/Memory stats."
echo "If you don't see it immediately, it may take a few seconds to appear."