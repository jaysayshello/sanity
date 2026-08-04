#!/usr/bin/env bash
# Render the app icon and build icon/Sanity.icns.
set -euo pipefail
cd "$(dirname "$0")"

PNG="icon/icon-1024.png"
ICONSET="icon/Sanity.iconset"
ICNS="icon/Sanity.icns"

swift icon/render-icon.swift "${PNG}"

rm -rf "${ICONSET}"; mkdir -p "${ICONSET}"
for spec in \
  "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
  "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
  "512:512x512" "1024:512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "${px}" "${px}" "${PNG}" --out "${ICONSET}/icon_${name}.png" >/dev/null
done

iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"
echo "Done: ${ICNS}"
