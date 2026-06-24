#!/bin/bash
set -e

# Usage helper
usage() {
    echo "Usage: $0 <version_number>"
    echo "Example: $0 1.0.12"
    exit 1
}

# Ensure a version number is provided
if [ -z "$1" ]; then
    usage
fi

# Clean version number (strip leading 'v' if present)
VERSION="${1#v}"

# Regexp to validate semantic version (X.Y.Z)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Error: Version number must be in semantic versioning format (e.g. 1.0.12)"
    exit 1
fi

echo "🚀 Starting release build for PhotoPrint v$VERSION..."

# 1. Update version in Info.plist
echo "📝 Updating Info.plist version strings to $VERSION..."
if ! command -v /usr/libexec/PlistBuddy &> /dev/null; then
    echo "❌ Error: PlistBuddy not found at /usr/libexec/PlistBuddy"
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist

# 2. Run local build script
echo "🛠️ Compiling application..."
./build.sh

# 3. Detect signing identity
echo "🔑 Finding codesigning identity..."
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    # Auto-detect the first Developer ID Application identity
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"(Developer ID Application: [^"]*)".*/\1/')
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "❌ Error: No 'Developer ID Application' codesigning identity found in Keychain."
    echo "To sign the application, you must install a Developer ID Application certificate from Apple."
    echo "You can also specify it manually using the APPLE_SIGNING_IDENTITY environment variable."
    echo "Example: export APPLE_SIGNING_IDENTITY=\"Developer ID Application: Daniel Zaharia (GM7Q7QYQN8)\""
    exit 1
fi

echo "✍️ Signing application with: \"$SIGNING_IDENTITY\""
# Sign the binary first with Hardened Runtime and Timestamp
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "PhotoPrint.app/Contents/MacOS/PhotoPrint"
# Sign the bundle
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "PhotoPrint.app"

# Verify signature
echo "🔍 Verifying signature..."
codesign --verify --verbose --deep "PhotoPrint.app"

# 4. Notarization
echo "📦 Packaging for notarization..."
ZIP_PATH="PhotoPrint_notary_temp.zip"
rm -f "$ZIP_PATH"
# Use ditto to create a zip preserving resource forks and HFS metadata
ditto -c -k --keepParent PhotoPrint.app "$ZIP_PATH"

echo "☁️ Submitting to Apple Notarization Service..."
NOTARY_ARGS=()

# Determine notarization authentication method
if [ -n "$NOTARY_KEY_ID" ] && [ -n "$NOTARY_ISSUER" ] && [ -n "$NOTARY_KEY_FILE" ]; then
    echo "🔑 Authenticating using App Store Connect API Key..."
    NOTARY_ARGS+=(--key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --key "$NOTARY_KEY_FILE")
elif [ -n "$NOTARY_APPLE_ID" ] && [ -n "$NOTARY_PASSWORD" ] && [ -n "$NOTARY_TEAM_ID" ]; then
    echo "🔑 Authenticating using Apple ID and App-Specific Password..."
    NOTARY_ARGS+=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
else
    # Default to keychain profile
    PROFILE="${NOTARY_PROFILE:-PhotoPrint}"
    echo "🔑 Authenticating using Keychain Profile: \"$PROFILE\"..."
    
    # Check if the profile exists in credentials list
    if ! xcrun notarytool history --keychain-profile "$PROFILE" &> /dev/null; then
        echo "❌ Error: Keychain profile \"$PROFILE\" not found or credentials invalid."
        echo "Please set up a keychain profile using xcrun notarytool:"
        echo "  xcrun notarytool store-credentials \"$PROFILE\" --apple-id \"your-apple-id@email.com\" --team-id \"YOUR_TEAM_ID\" --password \"your-app-specific-password\""
        echo ""
        echo "Or set the environment variables for notarization:"
        echo "  export NOTARY_APPLE_ID=\"your-apple-id@email.com\""
        echo "  export NOTARY_PASSWORD=\"your-app-specific-password\""
        echo "  export NOTARY_TEAM_ID=\"YOUR_TEAM_ID\""
        echo ""
        echo "Or set the environment variables for API key:"
        echo "  export NOTARY_KEY_ID=\"KEY_ID\""
        echo "  export NOTARY_ISSUER=\"ISSUER_ID\""
        echo "  export NOTARY_KEY_FILE=\"path/to/AuthKey_KEY_ID.p8\""
        rm -f "$ZIP_PATH"
        exit 1
    fi
    NOTARY_ARGS+=(--keychain-profile "$PROFILE")
fi

# Submit and wait
xcrun notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait

# Clean up temp zip
rm -f "$ZIP_PATH"

# 5. Stapling
echo "📎 Stapling notarization ticket to PhotoPrint.app..."
xcrun stapler staple PhotoPrint.app

# Verify stapler
echo "🔍 Validating staple ticket..."
xcrun stapler validate PhotoPrint.app

# 6. Stage changes in Git
echo "💾 Staging changes in git..."
git add Info.plist PhotoPrint.app

echo "🎉 Success! Release v$VERSION build, codesigning, and notarization completed."
echo "--------------------------------------------------------"
echo "To publish this release to GitHub, run:"
echo "  git commit -m \"Release v$VERSION\""
echo "  git tag v$VERSION"
echo "  git push origin main v$VERSION"
echo "--------------------------------------------------------"
