#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

PRODUCT_NAME="swift-generator"
VERSION="${1:-0.0.1}"
BUILD_DIR="build"
ARM64_DIR="${BUILD_DIR}/arm64"
X86_64_DIR="${BUILD_DIR}/x86_64"
BUNDLE_NAME="${PRODUCT_NAME}.artifactbundle"
BUNDLE_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
VARIANT_DIR="${BUNDLE_DIR}/${PRODUCT_NAME}-macos"
ZIP_NAME="${BUNDLE_NAME}.zip"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SwiftGenerator — Release Build     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""
info "Version: ${VERSION}"

# ─── Clean ────────────────────────────────────────
info "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${ARM64_DIR}" "${X86_64_DIR}" "${VARIANT_DIR}"

# ─── Build arm64 ──────────────────────────────────
info "Building for arm64..."
swift build -c release --arch arm64
cp "$(swift build -c release --arch arm64 --show-bin-path)/${PRODUCT_NAME}" "${ARM64_DIR}/${PRODUCT_NAME}"
success "arm64 build complete."

# ─── Build x86_64 ─────────────────────────────────
info "Building for x86_64..."
swift build -c release --arch x86_64
cp "$(swift build -c release --arch x86_64 --show-bin-path)/${PRODUCT_NAME}" "${X86_64_DIR}/${PRODUCT_NAME}"
success "x86_64 build complete."

# ─── Create universal binary ──────────────────────
info "Creating universal binary with lipo..."
lipo -create \
	"${ARM64_DIR}/${PRODUCT_NAME}" \
	"${X86_64_DIR}/${PRODUCT_NAME}" \
	-output "${VARIANT_DIR}/${PRODUCT_NAME}"
success "Universal binary created."

# ─── Verify ───────────────────────────────────────
info "Verifying universal binary..."
lipo -info "${VARIANT_DIR}/${PRODUCT_NAME}"

# ─── Create artifact bundle manifest ──────────────
info "Creating artifact bundle manifest..."
cat > "${BUNDLE_DIR}/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "${PRODUCT_NAME}": {
      "version": "${VERSION}",
      "type": "executable",
      "variants": [
        {
          "path": "${PRODUCT_NAME}-macos/${PRODUCT_NAME}",
          "supportedTriples": [
            "x86_64-apple-macosx",
            "arm64-apple-macosx"
          ]
        }
      ]
    }
  }
}
EOF
success "Artifact bundle manifest created."

# ─── Zip (artifact bundle for SPM) ────────────────
info "Creating artifact bundle zip..."
cd "${BUILD_DIR}"
zip -r "${ZIP_NAME}" "${BUNDLE_NAME}"
cd - > /dev/null
success "Archive created: ${BUILD_DIR}/${ZIP_NAME}"

# ─── Zip (plain binary for mise/ubi) ──────────────
PLAIN_ZIP="${PRODUCT_NAME}-macos-universal.zip"
info "Creating plain binary zip for mise..."
cp "${VARIANT_DIR}/${PRODUCT_NAME}" "${BUILD_DIR}/${PRODUCT_NAME}"
cd "${BUILD_DIR}"
zip "${PLAIN_ZIP}" "${PRODUCT_NAME}"
rm "${PRODUCT_NAME}"
cd - > /dev/null
success "Archive created: ${BUILD_DIR}/${PLAIN_ZIP}"

# ─── Checksum ─────────────────────────────────────
info "Computing checksum..."
CHECKSUM=$(swift package compute-checksum "${BUILD_DIR}/${ZIP_NAME}")
echo ""
success "Release build complete!"
echo ""
echo -e "  SPM artifact bundle: ${BLUE}${BUILD_DIR}/${ZIP_NAME}${NC}"
echo -e "  mise/ubi binary:     ${BLUE}${BUILD_DIR}/${PLAIN_ZIP}${NC}"
echo -e "  SPM checksum:        ${GREEN}${CHECKSUM}${NC}"
echo ""
