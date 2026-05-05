#!/bin/bash
# Cleans Square SDK xcframeworks at pod-install time so the build scripts
# copy clean content into PODS_XCFRAMEWORKS_BUILD_DIR.

set -euo pipefail

# Resolve script directory so this works regardless of calling directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PODS_DIR="${SCRIPT_DIR}/Pods"

if [ ! -d "${PODS_DIR}" ]; then
  echo "Pods directory not found at ${PODS_DIR}, skipping."
  exit 0
fi

echo "Fixing Square SDK in ${PODS_DIR}..."

for SDK in "SquareInAppPaymentsSDK" "SquareBuyerVerificationSDK"; do
  SDK_DIR="${PODS_DIR}/${SDK}"
  if [ ! -d "${SDK_DIR}" ]; then
    continue
  fi

  echo "Cleaning ${SDK}..."

  # Remove unsigned 'setup' executables only.
  # Do NOT delete nested Frameworks/ dirs here — CorePaymentCard.framework
  # lives inside SquareInAppPaymentsSDK.xcframework and must survive to
  # be extracted at build time by the "Fix Square SDK" Xcode build phase.
  find "${SDK_DIR}" -name "setup" -type f -delete 2>/dev/null || true
done

echo "Square SDK fix complete."