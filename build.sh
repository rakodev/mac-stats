#!/bin/bash

# Build script for MacStats
# This script builds the app for distribution

set -e

# Configuration
PROJECT_NAME="MacStats"
SCHEME_NAME="MacStats"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/MacStats.xcarchive"
EXPORT_PATH="./build/export"
APP_PATH="./build/export/MacStats.app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Building MacStats...${NC}"

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Error: Xcode command line tools not found${NC}"
    echo "Please install Xcode command line tools with: xcode-select --install"
    exit 1
fi

# Create build directory
mkdir -p build

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
rm -rf build/*

# Build archive
echo -e "${YELLOW}🔨 Building archive...${NC}"
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# Create export options plist
cat > build/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

# Export archive
echo -e "${YELLOW}📦 Exporting app...${NC}"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist build/ExportOptions.plist

# Create DMG (if create-dmg is available)
if command -v create-dmg &> /dev/null; then
    echo -e "${YELLOW}💿 Creating DMG...${NC}"
    create-dmg \
        --volname "MacStats Installer" \
        --window-pos 200 120 \
        --window-size 600 300 \
        --icon-size 100 \
        --app-drop-link 425 120 \
        "build/MacStats-Installer.dmg" \
        "${APP_PATH}"
else
    echo -e "${YELLOW}⚠️  create-dmg not found. Skipping DMG creation.${NC}"
    echo "To create a DMG, install create-dmg with: brew install create-dmg"
fi

# Create ZIP archive
echo -e "${YELLOW}🗜️  Creating ZIP archive...${NC}"
cd build/export
zip -r "../MacStats.zip" MacStats.app
cd ../..

echo -e "${GREEN}✅ Build completed successfully!${NC}"
echo -e "${GREEN}📁 App location: ${APP_PATH}${NC}"
echo -e "${GREEN}📁 ZIP archive: ./build/MacStats.zip${NC}"

if [ -f "build/MacStats-Installer.dmg" ]; then
    echo -e "${GREEN}📁 DMG installer: ./build/MacStats-Installer.dmg${NC}"
fi

echo ""
echo -e "${GREEN}🎉 MacStats is ready for distribution!${NC}"