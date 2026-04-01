# Code Signing Guide

## Why Code Signing?

Security software like CrowdStrike flags unsigned binaries that intercept keyboard events as potential malware. Code signing proves the app's authenticity and makes it look like a legitimate macOS application.

## Prerequisites

- Apple Developer Account (free or paid)
- Xcode Command Line Tools installed
- Valid signing certificate

## Quick Start

1. **Find your signing identity:**
   ```bash
   security find-identity -v -p codesigning
   ```

   Look for something like:
   ```
   1) ABC123... "Developer ID Application: Your Name (TEAM123)"
   ```

2. **Build and sign:**
   ```bash
   zig build bundle
   ./sign.sh "Developer ID Application: Your Name (TEAM123)"
   ```

3. **Verify:**
   ```bash
   codesign --verify --verbose zig-out/Deft.app
   spctl --assess --verbose zig-out/Deft.app
   ```

## What Gets Signed

The `sign.sh` script signs the app with:
- **Developer ID Application** certificate (for distribution outside App Store)
- **Hardened Runtime** enabled (`--options runtime`)
- **Entitlements** declared in `entitlements.plist`
- **Deep signing** to sign all nested components

## Bundle Structure

```
Deft.app/
├── Contents/
│   ├── Info.plist          # Bundle metadata, privacy descriptions
│   ├── MacOS/
│   │   └── deft            # The actual executable
│   └── Resources/          # (empty for now)
```

## Info.plist Highlights

- **Bundle Identifier**: `com.rayou.deft`
- **LSUIElement**: true (no dock icon, menu bar only)
- **Privacy Descriptions**: Explains why Accessibility/Input Monitoring are needed
- **Version**: 1.0.0

## Troubleshooting

### "No identity found"
You need to create a signing certificate in Xcode:
1. Open Xcode → Settings → Accounts
2. Add your Apple ID
3. Manage Certificates → + → Apple Development

### "User canceled"
The certificate is in your keychain but locked. Unlock it:
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

### CrowdStrike still flags it
Contact your IT team with:
- Bundle ID: `com.rayou.deft`
- Path: `/Applications/Deft.app`
- Signature: (verified via `codesign -dv Deft.app`)
- Purpose: Personal ergonomic keyboard customization tool

## Distribution

To share with others on the same corporate network:

1. Sign with Developer ID (not Apple Development)
2. Notarize with Apple (requires paid developer account):
   ```bash
   xcrun notarytool submit Deft.app.zip \
     --apple-id your.email@example.com \
     --team-id TEAM123 \
     --password "app-specific-password"
   ```
3. Staple the notarization ticket:
   ```bash
   xcrun stapler staple Deft.app
   ```

Notarization tells CrowdStrike and other security software that Apple has verified the app.
