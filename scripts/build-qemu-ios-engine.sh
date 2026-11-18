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
    echo "Selected original iPhone 2G (S5L8900 / m68ap), machine: iPhone-2G."
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

if [ "$DEVICE_TARGET" = "iphone4" ]; then
  # Stage the copied N90/A4 board sources.
  QEMU_SOURCE_DIR="$ENGINE" "$ROOT/scripts/stage-qemu-iphone4.sh"
elif [ "$DEVICE_TARGET" = "iphone2g" ]; then
  # The pinned QEMU-iOS source already contains the complete S5L8900 machine:
  # iPhone-2G is an m68ap board subtype of iPod-Touch-1G. Ensure the machine,
  # its source registration, and the default arm-softmmu config are present.
  grep -q 'TYPE_IPHONE_2G' "$ENGINE/hw/arm/ipod_touch_1g.c" || die "Pinned QEMU source lacks the iPhone-2G machine subtype."
  grep -q 'config IPOD_TOUCH_1G' "$ENGINE/hw/arm/Kconfig" || die "Pinned QEMU source lacks CONFIG_IPOD_TOUCH_1G."
  grep -q "CONFIG_IPOD_TOUCH_1G=y" "$ENGINE/configs/devices/arm-softmmu/default.mak" || die "arm-softmmu default config does not enable the S5L8900/iPhone 2G board."
  grep -q "CONFIG_IPOD_TOUCH_1G.*ipod_touch_1g.c" "$ENGINE/hw/arm/meson.build" || die "Meson does not register the S5L8900/iPhone 2G board sources."
  echo "Verified the pinned QEMU-iOS S5L8900 machine and iPhone-2G board registration."
else
  die "iPhone 3G board integration is still pending."
fi

# The application expects an iOS-device arm64 dynamic library with a defined
# embedding ABI at ios/Frameworks/libqemu-arm.dylib. A generic QEMU executable,
# macOS dylib, or static archive is not a substitute. No supported iOS-device
# QEMU library target/ABI is currently defined in this repository.
die "The selected QEMU board sources are present, but this repository still lacks the iOS arm64 libqemu-arm.dylib build target and app-facing QEMU embedding ABI. Refusing to emit an invalid artifact. Add the iOS cross-file, QEMU library target/export shim, and link contract before enabling this build."
