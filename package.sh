#!/usr/bin/env bash
# package.sh
# Build the distributable zip for the Iron addon.
#
# The zip contains ONLY the Iron/ addon folder. No markdown, no scripts, no
# screenshots, no .github, no internal docs. Exactly what an end user drops
# into Interface/AddOns/.
#
# Output: Iron-<version>.zip in the repo root.
# Version is read from Iron/Iron.toc.

set -euo pipefail

ADDON_DIR="Iron"
TOC="${ADDON_DIR}/Iron.toc"

if [ ! -f "${TOC}" ]; then
  echo "[package] ${TOC} not found. Run from repo root."
  exit 1
fi

VERSION=$(grep "^## Version:" "${TOC}" | awk '{print $3}')
if [ -z "${VERSION}" ]; then
  echo "[package] Could not read version from ${TOC}. Expected line '## Version: X.Y.Z'."
  exit 1
fi

# Asset name is fixed: Iron.zip. Version is tracked via the git tag and the .toc.
# This matches what WoW addon updaters expect and keeps download URLs predictable.
ZIP_NAME="Iron.zip"

# Clean any previous build with the same name so we never ship stale bytes.
rm -f "${ZIP_NAME}"

# Zip only the addon folder. -x excludes anything that should not ship.
zip -r "${ZIP_NAME}" "${ADDON_DIR}" \
  -x "${ADDON_DIR}/.*" \
  -x "${ADDON_DIR}/**/.*" \
  -x "${ADDON_DIR}/**/*.bak" \
  -x "${ADDON_DIR}/**/*.lua~" \
  -x "${ADDON_DIR}/**/Thumbs.db" \
  -x "${ADDON_DIR}/**/.DS_Store" \
  > /dev/null

echo "[package] Built ${ZIP_NAME}"
echo "[package] Contents (top level):"
unzip -l "${ZIP_NAME}" | head -n 20
