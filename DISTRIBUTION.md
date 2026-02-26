# MacStats Distribution Guide

This guide covers how to build and distribute MacStats as a signed and notarized macOS app.

## Prerequisites

- Apple Developer Program membership ($99/year)
- Developer ID Application certificate installed in Keychain

## Setup (One-Time)

### 1. Create Developer ID Application Certificate

If you haven't already:

1. Open **Xcode → Settings → Accounts**
2. Select your Apple ID → click your team
3. Click **Manage Certificates**
4. Click **+** → **Developer ID Application**

Verify it's installed:
```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see:
```
"Developer ID Application: Ramazan KORKMAZ (K542B2Z65M)"
```

### 2. Create App-Specific Password for Notarization

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign In
2. Go to **Sign-In and Security** → **App-Specific Passwords**
3. Click **+** to generate a new password
4. Name it "notarytool" or similar
5. Copy the password (you'll only see it once)

### 3. Store Notarization Credentials in Keychain

> **Note:** This project reuses the same notarization credentials as MacClipboard (`MacClipboard-Notarize` keychain profile), since both apps are published under the same Apple Developer account.

If you need to set up credentials on a new machine:

```bash
xcrun notarytool store-credentials "MacClipboard-Notarize" \
  --apple-id "ramax@atalist.com" \
  --team-id "K542B2Z65M"
```

When prompted, enter an app-specific password from appleid.apple.com.

**Current configuration:**

| Setting | Value |
|---------|-------|
| Keychain Profile | `MacClipboard-Notarize` |
| Apple ID | `ramax@atalist.com` |
| Team ID | `K542B2Z65M` |

This is stored securely in your macOS Keychain, not in any file.

## Building for Distribution

### Quick Build (After Setup)

```bash
./build.sh
```

This will:
1. Build the app in Release configuration
2. Sign it with your Developer ID
3. Notarize it with Apple
4. Staple the notarization ticket
5. Create a ZIP and optional DMG for distribution

### Full Release

```bash
./build.sh release
```

This will do everything above plus:
1. Handle uncommitted changes
2. Bump version in Xcode project
3. Create git tag and push
4. Create GitHub release with assets
5. Update Homebrew tap

### Output Files

After a successful build, you'll find:
- `./build/export/MacStats.app` - The signed app bundle
- `./build/MacStats.zip` - ZIP archive for sharing
- `./build/MacStats-Installer.dmg` - DMG installer (if create-dmg is installed)

### Optional: Install create-dmg

For a nicer DMG installer with drag-to-Applications:

```bash
brew install create-dmg
```

## Distribution

### Distribution Methods

| Method | Audience | Install Command |
|--------|----------|-----------------|
| GitHub Releases | Developers, early adopters | Download from releases page |
| Homebrew Cask | Developers | `brew install --cask rakodev/tap/macstats` |
| Direct Download | Everyone | Download from website |

## Homebrew Cask

The cask formula is maintained in the [homebrew-tap](https://github.com/rakodev/homebrew-tap) repository at `Casks/macstats.rb`.

Users install with:
```bash
brew tap rakodev/tap
brew install --cask macstats
```

The `build.sh release` script automatically updates the cask version and SHA256.

## Troubleshooting

### Certificate Not Found

```bash
security find-identity -v -p codesigning
```

If your Developer ID certificate doesn't appear, try:
1. Open Keychain Access
2. Check both "login" and "System" keychains
3. Re-download the certificate from developer.apple.com

### Notarization Fails

Check the notarization log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "MacClipboard-Notarize"
```

Common issues:
- Hardened Runtime not enabled
- Missing entitlements
- Unsigned embedded frameworks

### Verify Notarization Status

```bash
spctl -a -vvv -t install ./build/export/MacStats.app
```

Should show: `source=Notarized Developer ID`
