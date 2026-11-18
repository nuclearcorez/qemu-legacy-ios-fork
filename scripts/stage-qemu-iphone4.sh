#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENGINE="${QEMU_SOURCE_DIR:-$ROOT/vendor/qemu-engine}"
VENDOR="$ROOT/vendor/qemu-iphone4"

if [ ! -d "$ENGINE" ]; then
  echo "QEMU engine source not found at: $ENGINE" >&2
  echo "Initialize the pinned submodule with: git submodule update --init --recursive" >&2
  echo "To use another compatible checkout, set QEMU_SOURCE_DIR." >&2
  exit 2
fi

if [ ! -f "$ENGINE/meson.build" ] || [ ! -f "$ENGINE/hw/arm/meson.build" ]; then
  echo "QEMU source tree not found or incomplete at: $ENGINE" >&2
  exit 2
fi

for subtree in hw/arm hw/misc include/hw/arm include/hw/misc include/hw/net; do
  if [ -d "$VENDOR/$subtree" ]; then
    mkdir -p "$ENGINE/$subtree"
    cp -R "$VENDOR/$subtree/." "$ENGINE/$subtree/"
  fi
done

# The iOS SDK does not include OpenSSL headers. The iPhone AES peripheral only
# uses AES_set_{encrypt,decrypt}_key and AES_cbc_encrypt, provided by the
# vendored CommonCrypto compatibility shim for Apple targets.
if [ -f "$VENDOR/include/openssl/aes.h" ]; then
  mkdir -p "$ENGINE/include/openssl"
  cp "$VENDOR/include/openssl/aes.h" "$ENGINE/include/openssl/aes.h"
fi
if [ ! -f "$ENGINE/include/openssl/aes.h" ]; then
  echo "Missing iOS AES compatibility header: include/openssl/aes.h" >&2
  exit 5
fi

if [ -f "$VENDOR/include/openssl/bn.h" ]; then
  cp "$VENDOR/include/openssl/bn.h" "$ENGINE/include/openssl/bn.h"
fi
if [ ! -f "$ENGINE/include/openssl/bn.h" ]; then
  echo "Missing GMP-backed iOS BIGNUM compatibility header: include/openssl/bn.h" >&2
  exit 5
fi

# QEMU's source include paths use -iquote, so the vendored compatibility
# header must be included with quotes rather than angle brackets.
python3 - "$ENGINE/hw/arm/ipod_touch_pke.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
text = text.replace("#include <openssl/bn.h>", '#include "openssl/bn.h"', 1)
p.write_text(text)
PY

# The A4 board also calls into the shared iPod Touch support modules. They
# are copied into the engine tree above, but the upstream IPAD1 Meson stanza
# only lists the board-specific files. Register the shared implementations
# here or the final link leaves their symbols unresolved.
SHARED_A4_SOURCES="
  guest-services.c guest-pasteboard.c guest-package.c ipod-agent.c guest-gles.c ios-posix-compat.c
  it_iboot.c ipod_touch_clock.c ipod_touch_chipid.c ipod_touch_gpio.c
  ipod_touch_sysic.c ipod_touch_timer.c ipod_touch_spi.c ipod_touch_nor_spi.c
  ipod_touch_sha1.c ipod_touch_aes.c ipod_touch_pke.c ipod_touch_pcf50633_pmu.c
  ipod_touch_unknown1.c ipod_touch_wdt.c ipod_touch_mpvd.c ipod_touch_h264.c
  ipod_touch_scaler.c ipod_touch_swi.c ipod_video.c ipod_touch_lcd.c
  ipod_touch_mipi_dsi.c ipod_touch_fmss.c ipod_touch_mbx.c
  ipod_touch_cd3272_mikey.c ipod_touch_cs42l58.c ipod_touch_amc.c
  ipod_touch_i2s.c ipod_touch_lm48821.c ipod_touch_lis302dl.c
  ipod_touch_tethered.c ipod_touch_multitouch.c ipod_touch_tvout.c
  ipod_touch_isl29003dl.c ipod_touch_bt.c
  ipod_touch_usb_otg.c ipod_touch_tcp_usb.c ipod_touch_usb_phys.c
"
for source in $SHARED_A4_SOURCES; do
  if [ ! -f "$ENGINE/hw/arm/$source" ]; then
    echo "Missing shared A4 support source: hw/arm/$source" >&2
    exit 4
  fi
done

# Keep this list aligned with the pinned CONFIG_IPAD1 source registrations.
for source in \
  ipad1.c s5l8930_dmc.c s5l8930_pmgr.c s5l8930_gpio.c \
  s5l8930_iop.c s5l8930_iop_core.c s5l8930_sdio.c s5l8930_i2c.c \
  s5l8930_display.c s5l8930_dart.c s5l8930_cdma.c s5l8930_bbspi.c \
  s5l8930_h2fmi.c s5l8930_sha1.c s5l8930_ltc4099.c s5l8930_hdq.c \
  s5l8930_i2s.c s5l8930_isp.c s5l8940_isp.c img_topaz.c img_topaz_h264.c \
  s5l8920.c s5l8920_pmgr.c s5l8920_dart.c s5l8920_pwm.c \
  s5l8920_vxd.c s5l8920_vxd_h264.c s5l8920_jpeg.c \
  s5l8950.c cs42l65.c cs35l19.c nand-image.c tsl2561.c \
  ipod_touch_sdio.c bcm_fullmac.c mrvl8686.c; do
  if [ ! -f "$ENGINE/hw/arm/$source" ]; then
    echo "Missing staged CONFIG_IPAD1 source: hw/arm/$source" >&2
    exit 4
  fi
done

for header in ipod_touch_sdio.h mrvl8686.h; do
  if [ ! -f "$ENGINE/include/hw/arm/$header" ]; then
    echo "Missing staged Wi-Fi header: include/hw/arm/$header" >&2
    exit 5
  fi
done
if [ ! -f "$ENGINE/include/hw/net/bcm_fullmac.h" ]; then
  echo "Missing staged Wi-Fi header: include/hw/net/bcm_fullmac.h" >&2
  exit 5
fi

grep -q "CONFIG_IPAD1" "$ENGINE/hw/arm/meson.build" || {
  echo "QEMU engine is missing CONFIG_IPAD1 source registration." >&2
  exit 3
}
grep -q "config IPAD1" "$ENGINE/hw/arm/Kconfig" || {
  echo "QEMU engine is missing the IPAD1 Kconfig option." >&2
  exit 3
}

echo "Staged copied iPhone 4 GSM (n90ap/A4) sources into: $ENGINE"
echo "Select the GSM iPhone 4 board with -M iPhone-4 (not -M ipad1)."
echo "N90 uses Samsung 0xB614D5AD (4 KiB pages, 128 pages/block); the 8 GiB profile uses two CEs on each of two buses."
echo "The BCM4329 Wi-Fi bridge is enabled by default; it auto-creates user-mode NAT networking as wifi0."
echo "The CONFIG_IPAD1 Meson registration below enables the BCM4329 SDIO card models."

# Register shared A4 support before hw_arch exports arm_ss. Appending these
# declarations to the end of Meson file silently omits them from the build.
python3 "$ROOT/scripts/patch-qemu-iphone4-meson.py" "$ENGINE/hw/arm/meson.build"

TRACE_EVENTS="$ENGINE/hw/arm/trace-events"
TRACE_FRAGMENT="$VENDOR/upstream/hw/arm/trace-events"
if [ ! -f "$TRACE_EVENTS" ] || [ ! -f "$TRACE_FRAGMENT" ]; then
  echo "QEMU hw/arm/trace-events or the vendored Wi-Fi trace fragment is missing." >&2
  exit 5
fi
if ! grep -q "ipod_touch_sdio_log" "$TRACE_EVENTS"; then
  cat "$TRACE_FRAGMENT" >> "$TRACE_EVENTS"
fi

echo "Generic QEMU dependencies and firmware images must be supplied separately."
