#!/bin/bash
# AquaTech Weather — Build Script
# Run this on your Mac to build the desktop app

echo "=== AquaTech Weather — Building Desktop App ==="
echo ""

# Clean old build artifacts so nothing is cached
echo "[1/4] Cleaning old builds..."
rm -rf dist/

# Install dependencies
echo "[2/4] Installing dependencies..."
npm install
if [ $? -ne 0 ]; then
    echo "ERROR: npm install failed"
    exit 1
fi

# Rebuild native modules for Electron
echo "[3/4] Rebuilding native modules for Electron..."
npx electron-builder install-app-deps
if [ $? -ne 0 ]; then
    echo "ERROR: native module rebuild failed"
    exit 1
fi

# Build the macOS app
echo "[4/4] Building macOS app..."
npm run build:mac
if [ $? -ne 0 ]; then
    echo "ERROR: build failed"
    exit 1
fi

echo ""
echo "=== BUILD COMPLETE ==="
echo "Your app is in the dist/ folder:"
ls -la dist/*.dmg dist/*.zip 2>/dev/null
echo ""
echo "Open the .dmg to install, or unzip the .zip to run directly."
echo ""
echo "NOTE: If you previously installed the web version (PWA),"
echo "open Chrome, go to the site, click the 3-dot menu → App info → Remove."
echo "Then reinstall from the browser to get the updated employee version."
