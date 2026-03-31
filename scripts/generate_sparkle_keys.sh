#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# generate_sparkle_keys.sh — Generate EdDSA key pair for Sparkle update signing
#
# Run ONCE when setting up the release pipeline for the first time.
# The private key must be stored securely (never committed to git).
#
# After running:
#   1. Copy the PUBLIC KEY into Voxema/Info.plist → SUPublicEDKey
#   2. Store the private key as SPARKLE_PRIVATE_KEY GitHub secret (base64)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SPARKLE_VERSION="2.6.4"
TOOLS_DIR="$(mktemp -d)"
TOOLS_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

echo "▶ Downloading Sparkle CLI tools v${SPARKLE_VERSION}…"
curl -sSL "$TOOLS_URL" -o "$TOOLS_DIR/sparkle.zip"
unzip -q "$TOOLS_DIR/sparkle.zip" -d "$TOOLS_DIR/sparkle"

echo ""
echo "▶ Generating EdDSA key pair…"
echo ""

"$TOOLS_DIR/sparkle/bin/generate_keys"

echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "NEXT STEPS:"
echo ""
echo "1. Copy the PUBLIC KEY shown above."
echo "   Paste it into Voxema/Info.plist as the value for SUPublicEDKey:"
echo "   Replace: PLACEHOLDER_REPLACE_WITH_OUTPUT_OF_generate_keys"
echo ""
echo "2. Copy the PRIVATE KEY shown above."
echo "   Go to GitHub → Settings → Secrets → Actions → New secret:"
echo "   Name:  SPARKLE_PRIVATE_KEY"
echo "   Value: <base64-encoded private key>"
echo ""
echo "   To base64-encode: echo 'YOUR_PRIVATE_KEY' | base64"
echo ""
echo "3. NEVER commit the private key to git."
echo "─────────────────────────────────────────────────────────────────"

rm -rf "$TOOLS_DIR"
