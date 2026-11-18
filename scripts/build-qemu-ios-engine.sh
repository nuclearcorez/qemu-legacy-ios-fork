#!/usr/bin/env bash
# Project Astra QEMU iOS engine build entry point.
#
# This script deliberately refuses to publish a fake/host-architecture engine.
# The pinned qemu-ios tree is a QEMU source tree, but this repository does not
# yet contain an iOS device cross-build configuration or the libqemu-arm.dylib
# embedding/export layer consumed by the SwiftUI app.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${QEMU_SOURCE_DIR:-$ROOT/vendor/qemu-engine}"
BUILD_ROOT="${QEMU_IOS_BUILD_ROOT:-$ROOT/.build/qemu-ios}"
DEVICE_TARGET="${DEVICE_TARGET:-iphone4}"

die() {
  echo "::error::$*" >&2
  exit 1
}

case "$DEVICE_TARGET" in
  iphone4)
    echo "Selected target: iPhone 4 GSM (A4 / N90AP)."
    ;;
  iphone2g)
    die "iPhone 2G (S5L8900 / m68ap) has no integrated machine registration or boot pipeline yet."
    ;;
  iphone3g)
    die "iPhone 3G (S5L8900 / N82AP) has no integrated machine registration or boot pipeline yet."
    ;;
  *)
    die "Unsupported DEVICE_TARGET '$DEVICE_TARGET'. Choose iphone4, iphone2g, or iphone3g."
    ;;
esac

[[ -d "$ENGINE" ]] || die "QEMU source is missing at $ENGINE. Run: git submodule update --init --recursive"
[[ -f "$ENGINE/configure" ]] || die "Pinned QEMU source has no configure script: $ENGINE"
[[ -f "$ENGINE/meson.build" ]] || die "Pinned QEMU source is incomplete: $ENGINE/meson.build"
[[ -x "$(command -v xcrun || true)" ]] || die "Xcode command-line tools are required (xcrun not found)."
[[ "$(uname -s)" == Darwin ]] || die "The iOS device build must run on macOS."

mkdir -p "$BUILD_ROOT"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "iPhoneOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
echo "QEMU source revision: $(git -C "$ENGINE" rev-parse HEAD)"

# Stage the currently integrated N90/A4 board sources before validating the
# build integration. This script is intentionally not used for 2G/3G sources.
QEMU_SOURCE_DIR="$ENGINE" "$ROOT/scripts/stage-qemu-iphone4.sh"

# The application expects an iOS-device arm64 dynamic library with a defined
# embedding ABI at ios/Frameworks/libqemu-arm.dylib. A generic QEMU executable,
# macOS dylib, or static archive is not a substitute. No supported iOS-device
# QEMU library target/ABI is currently defined in this repository.
die "The N90/A4 sources are staged, but an iOS arm64 libqemu-arm.dylib build target and app-facing QEMU embedding ABI have not been implemented. Refusing to emit an invalid artifact. Add the iOS cross-file, QEMU library target/export shim, and link contract before enabling this build."
