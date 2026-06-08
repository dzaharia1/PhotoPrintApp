#!/bin/bash
set -e

# Base directory setup
APP_DIR="PhotoPrint.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🧹 Cleaning previous build..."
rm -rf "$APP_DIR"

echo "📂 Creating app bundle directories..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📝 Copying Info.plist..."
cp Info.plist "$CONTENTS_DIR/Info.plist"

echo "🎨 Copying AppIcon.icns..."
cp AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

echo "⚙️ Compiling Swift files..."
swiftc -parse-as-library -O \
  -target arm64-apple-macos26.0 \
  -o "$MACOS_DIR/PhotoPrint" \
  PhotoPrintApp.swift \
  Models.swift \
  LayoutEngine.swift \
  ImageCompositor.swift \
  PrinterManager.swift \
  ContentView.swift

echo "🔑 Setting executable permissions..."
chmod +x "$MACOS_DIR/PhotoPrint"

echo "🔗 Creating Applications symlink..."
ln -sfn "$PWD/PhotoPrint.app" "$HOME/Applications/PhotoPrint.app"

echo "🎉 Build completed successfully! Generated $APP_DIR"
