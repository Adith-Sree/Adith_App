#!/usr/bin/env bash
# android_sdk_setup.sh
# Downloads and installs Android command-line tools + required SDK packages.
# Run AFTER Java is installed.
# Usage: bash android_sdk_setup.sh

set -e

ANDROID_HOME="$HOME/Library/Android/sdk"
CMDLINE_TOOLS_DIR="$ANDROID_HOME/cmdline-tools"

echo "📦 Setting up Android SDK at: $ANDROID_HOME"
mkdir -p "$CMDLINE_TOOLS_DIR"

# Download latest command-line tools for macOS (ARM64)
TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
TOOLS_ZIP="/tmp/cmdline-tools.zip"

echo "⬇️  Downloading Android command-line tools..."
curl -L -o "$TOOLS_ZIP" "$TOOLS_URL"

echo "📂 Extracting..."
unzip -q "$TOOLS_ZIP" -d "$CMDLINE_TOOLS_DIR"

# Rename to 'latest' as required by sdkmanager
mv "$CMDLINE_TOOLS_DIR/cmdline-tools" "$CMDLINE_TOOLS_DIR/latest" 2>/dev/null || true

SDKMANAGER="$CMDLINE_TOOLS_DIR/latest/bin/sdkmanager"
echo "✅ sdkmanager available at: $SDKMANAGER"

# Accept all licenses
echo "📜 Accepting SDK licenses..."
yes | "$SDKMANAGER" --licenses > /dev/null 2>&1 || true

# Install required SDK packages for Flutter + Pixel 8 Pro (API 35)
echo "📦 Installing SDK packages (API 35, build-tools, platform-tools)..."
"$SDKMANAGER" \
  "platform-tools" \
  "platforms;android-35" \
  "build-tools;35.0.0" \
  "cmdline-tools;latest"

# Set ANDROID_HOME in shell profile
PROFILE="$HOME/.zshrc"
if ! grep -q "ANDROID_HOME" "$PROFILE"; then
  echo "" >> "$PROFILE"
  echo "# Android SDK" >> "$PROFILE"
  echo "export ANDROID_HOME=\"\$HOME/Library/Android/sdk\"" >> "$PROFILE"
  echo "export PATH=\"\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH\"" >> "$PROFILE"
  echo "✅ Added ANDROID_HOME to $PROFILE"
fi

# Wire flutter to the SDK
flutter config --android-sdk "$ANDROID_HOME"

echo ""
echo "✅ Android SDK setup complete!"
echo "   Run: source ~/.zshrc && flutter doctor"
