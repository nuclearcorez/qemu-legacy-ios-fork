#!/usr/bin/env python3
"""Register iPhone 4 shared support before QEMU exports the ARM source set."""
from pathlib import Path
import sys

meson = Path(sys.argv[1])
text = meson.read_text()
marker = "# Project Astra: shared A4 peripheral implementations."
# Remove our previous generated tail/fragment so rerunning staging is idempotent.
export_marker = "hw_arch += {'arm': arm_ss}"
if marker in text:
    start = text.index(marker)
    export_at = text.find(export_marker, start)
    if export_at >= 0:
        # Previous generated block was inserted before the export.
        text = text[:start] + text[export_at:]
    else:
        # Older generated block was appended after the export.
        text = text[:start]
if export_marker not in text:
    raise SystemExit("Could not find ARM source-set export in hw/arm/meson.build")

block = """
# Project Astra: shared A4 peripheral implementations.
# These must be added before hw_arch exports arm_ss.
arm_ss.add(when: 'CONFIG_IPAD1', if_true: files(
  'guest-services.c', 'guest-pasteboard.c', 'guest-package.c',
  'ipod-agent.c', 'guest-gles.c', 'it_iboot.c',
  'ipod_touch_clock.c', 'ipod_touch_chipid.c', 'ipod_touch_gpio.c',
  'ipod_touch_sysic.c', 'ipod_touch_timer.c', 'ipod_touch_spi.c',
  'ipod_touch_nor_spi.c', 'ipod_touch_sha1.c', 'ipod_touch_aes.c',
  'ipod_touch_pke.c', 'ipod_touch_pcf50633_pmu.c',
  'ipod_touch_unknown1.c', 'ipod_touch_wdt.c', 'ipod_touch_mpvd.c',
  'ipod_touch_h264.c', 'ipod_touch_scaler.c', 'ipod_touch_swi.c',
  'ipod_video.c', 'ipod_touch_lcd.c', 'ipod_touch_mipi_dsi.c',
  'ipod_touch_fmss.c', 'ipod_touch_mbx.c', 'ipod_touch_cd3272_mikey.c',
  'ipod_touch_cs42l58.c', 'ipod_touch_amc.c', 'ipod_touch_i2s.c',
  'ipod_touch_lm48821.c', 'ipod_touch_lis302dl.c', 'ipod_touch_tethered.c',
  'ipod_touch_multitouch.c', 'ipod_touch_tvout.c', 'ipod_touch_isl29003dl.c',
  'ipod_touch_bt.c', 'ipod_touch_usb_otg.c', 'ipod_touch_tcp_usb.c',
  'ipod_touch_usb_phys.c', 'gles-host-stub.c', 'ios-posix-compat.c'
))
# BCM4329 SDIO/full-MAC support for the GSM iPhone 4.
arm_ss.add(when: 'CONFIG_IPAD1', if_true: files(
  'ipod_touch_sdio.c', 'bcm_fullmac.c', 'mrvl8686.c'
))
"""
text = text.replace(export_marker, block + "\n" + export_marker, 1)
meson.write_text(text)
