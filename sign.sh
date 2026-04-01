#!/bin/bash
set -e

# Build the app
echo "Building..."
zig build

# Create .app bundle
echo "Creating .app bundle..."
zig build bundle

# Sign the app (replace with your Apple Developer ID)
IDENTITY="${1:-}"

if [ -z "$IDENTITY" ]; then
    echo ""
    echo "Usage: ./sign.sh \"Developer ID Application: Your Name\""
    echo ""
    echo "To find your signing identity, run:"
    echo "  security find-identity -v -p codesigning"
    echo ""
    echo "Example:"
    echo "  ./sign.sh \"Developer ID Application: John Doe (ABC123XYZ)\""
    exit 1
fi

echo "Signing with: $IDENTITY"
codesign --force --deep --sign "$IDENTITY" \
    --entitlements entitlements.plist \
    --options runtime \
    zig-out/Deft.app

echo ""
echo "Verifying signature..."
codesign --verify --verbose zig-out/Deft.app

echo ""
echo "Successfully signed Deft.app"
echo ""
echo "To run the app:"
echo "  open zig-out/Deft.app"
echo ""
echo "To install to Applications:"
echo "  cp -r zig-out/Deft.app /Applications/"
