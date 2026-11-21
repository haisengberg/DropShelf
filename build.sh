#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DropShelf"
ARCH="universal"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
MAKE_RELEASE=false
DO_INSTALL=false

BUNDLE_ID="${BUNDLE_ID:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MIN_MACOS="13.0"

usage() {
    cat <<EOF
Usage: ./build.sh [options]

Options:
  --arch <universal|arm64|x86_64>  Target architecture (default: universal)
  --output <dir>                   Output directory (default: ./dist)
  --release                        Also create versioned .zip archive and .sha256 checksum
  --install                        Copy built ${APP_NAME}.app into /Applications
  -h, --help                       Show this help message

Environment variables:
  BUNDLE_ID       Override CFBundleIdentifier (default: from Resources/Info.plist)
  VERSION         Override CFBundleShortVersionString (default: from Resources/Info.plist)
  BUILD_NUMBER    Override CFBundleVersion (default: from Resources/Info.plist)
  SIGN_IDENTITY   Codesign identity (default: "-" for ad-hoc signing)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="${2:?Missing value for --arch}"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="${2:?Missing value for --output}"
            shift 2
            ;;
        --release)
            MAKE_RELEASE=true
            shift
            ;;
        --install)
            DO_INSTALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "${ARCH}" in
    universal|arm64|x86_64) ;;
    *)
        echo "Unsupported --arch value: ${ARCH} (expected universal, arm64, or x86_64)" >&2
        exit 1
        ;;
esac

OUTPUT_APP="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${OUTPUT_APP}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"
echo "==> Preparing bundle at ${OUTPUT_APP}"
rm -rf "${OUTPUT_APP}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Generating AppIcon.icns"
ICONSET_DIR="${TMP_DIR}/AppIcon.iconset"
swift "${SCRIPT_DIR}/Scripts/generate_icon.swift" "${ICONSET_DIR}"
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"

SWIFT_FILES=("${SCRIPT_DIR}"/Sources/*.swift)
COMMON_FLAGS=(
    -O
    -framework AppKit
    -framework Foundation
    -framework Carbon
    -framework Quartz
    -framework ImageIO
)

compile_slice() {
    local slice_arch="$1"
    local out_bin="$2"
    echo "==> Compiling ${APP_NAME} (${slice_arch}, macOS ${MIN_MACOS}+)"
    swiftc \
        -target "${slice_arch}-apple-macosx${MIN_MACOS}" \
        "${COMMON_FLAGS[@]}" \
        "${SWIFT_FILES[@]}" \
        -o "${out_bin}"
}

if [[ "${ARCH}" == "universal" ]]; then
    compile_slice "arm64" "${TMP_DIR}/${APP_NAME}-arm64"
    compile_slice "x86_64" "${TMP_DIR}/${APP_NAME}-x86_64"
    echo "==> Combining arm64 + x86_64 with lipo"
    lipo -create \
        "${TMP_DIR}/${APP_NAME}-arm64" \
        "${TMP_DIR}/${APP_NAME}-x86_64" \
        -output "${MACOS_DIR}/${APP_NAME}"
else
    compile_slice "${ARCH}" "${MACOS_DIR}/${APP_NAME}"
fi

echo "==> Copying Info.plist"
PLIST_DEST="${CONTENTS_DIR}/Info.plist"
cp "${SCRIPT_DIR}/Resources/Info.plist" "${PLIST_DEST}"

if [[ -n "${BUNDLE_ID}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${PLIST_DEST}"
fi
if [[ -n "${VERSION}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST_DEST}"
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${PLIST_DEST}"
fi

RESOLVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PLIST_DEST}")"

echo "==> Signing ${APP_NAME}.app (identity: ${SIGN_IDENTITY})"
codesign --force --deep --sign "${SIGN_IDENTITY}" "${OUTPUT_APP}"
codesign --verify --deep --strict "${OUTPUT_APP}"

echo "==> Binary architectures:"
lipo -info "${MACOS_DIR}/${APP_NAME}"

if [[ "${MAKE_RELEASE}" == true ]]; then
    ARCHIVE_NAME="${APP_NAME}-${RESOLVED_VERSION}-${ARCH}.zip"
    ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"
    SHA_PATH="${ARCHIVE_PATH}.sha256"

    echo "==> Packaging release archive: ${ARCHIVE_PATH}"
    rm -f "${ARCHIVE_PATH}" "${SHA_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${OUTPUT_APP}" "${ARCHIVE_PATH}"
    (
        cd "${OUTPUT_DIR}"
        shasum -a 256 "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256"
    )
    echo "==> SHA-256:"
    cat "${SHA_PATH}"
fi

if [[ "${DO_INSTALL}" == true ]]; then
    echo "==> Installing to /Applications/${APP_NAME}.app"
    rm -rf "/Applications/${APP_NAME}.app"
    ditto "${OUTPUT_APP}" "/Applications/${APP_NAME}.app"
fi

echo "==> Done: ${OUTPUT_APP}"
