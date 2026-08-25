#!/usr/bin/env bash
# Build the shippable Illusory.app and zip it for distribution.
#
# Signing matters more than it looks. An unsigned or ad-hoc-signed app is not just
# "a scary warning": on Apple silicon, macOS refuses to grant Accessibility and
# Screen Recording to a build whose signature it cannot verify, and Illusory needs
# both. It will launch and then quietly do nothing.
#
#   DEVELOPER_ID   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE name of a stored notarytool keychain profile
#
# With both set this produces a build anyone can download and open. With neither,
# it produces one that only works on this machine.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(date +%Y.%m.%d)}"
APP="build/Illusory.app"
ZIP="build/Illusory.zip"

echo "==> Building release binary"
CONFIG=release ./scripts/bundle.sh >/dev/null

# bundle.sh stamps a dev version; overwrite it with the release one.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
  "$APP/Contents/Info.plist"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Signing with $DEVELOPER_ID"
  # Hardened runtime is required for notarisation.
  codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
else
  echo "!!  DEVELOPER_ID not set — ad-hoc signing."
  echo "!!  This build will run here but macOS will refuse it Accessibility and"
  echo "!!  Screen Recording on other machines, so Illusory will do nothing."
  codesign --force --sign - "$APP"
fi

echo "==> Zipping"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle's symlinks and extended attributes,
# and a plain zip breaks the signature.
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarising (this takes a few minutes)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  # The staple goes on the .app, then it is re-zipped so the download carries it
  # and opens without a network round trip on the user's machine.
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "==> Notarised and stapled"
else
  echo "!!  NOTARY_PROFILE not set — not notarised."
  echo "!!  Users will see \"Apple could not verify Illusory is free of malware\"."
fi

echo
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1)), version $VERSION"
echo
echo "Publish it with:"
echo "  gh release create v$VERSION $ZIP --title \"Illusory $VERSION\" --generate-notes"
