#!/usr/bin/env bash
# Build Sanity.app, then package it into a drag-to-install Sanity.dmg.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Sanity"
APP_DIR="build/${APP_NAME}.app"
DMG_PATH="build/${APP_NAME}.dmg"
STAGE="build/dmg"

./build-app.sh

echo "Staging disk image contents..."
rm -rf "${STAGE}" "${DMG_PATH}"
mkdir -p "${STAGE}"
cp -R "${APP_DIR}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

echo "Creating ${DMG_PATH}..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGE}"
echo "Done: ${DMG_PATH}"
echo "Install: open the dmg and drag ${APP_NAME} into Applications."
