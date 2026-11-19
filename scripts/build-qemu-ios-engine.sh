#!/usr/bin/env bash
# Cross-build the pinned QEMU-iOS ARM system emulator as an iOS ARM64 dylib.
# The iOS entry point and UIKit-facing ABI are upstream's contrib/ios-app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT/vendor/qemu-engine"
BUILD_ROOT="${QEMU_IOS_BUILD_ROOT:-${RUNNER_TEMP:-$ROOT/.build}/qemu-ios}"
DEVICE_TARGET="${DEVICE_TARGET:-iphone4}"
BOOT="$BUILD_ROOT/bootstrap"
IOS="$BUILD_ROOT/$DEVICE_TARGET/ios"
DEPS="$BUILD_ROOT/deps"
EXPECTED_ENGINE_SHA="db230fe8e8e4d297724b2eccdc38bdc21876696a"
DEPS_URL="https://github.com/MakrSas/orchard-ios/releases/download/ios-deps-1/orchard-ios-deps-arm64.tar.xz"
DEPS_SHA="c6da859237e603427e22b542b943f8a6c94ad09d5823e40838e0b0e87232a5cf"

test -f "$ENGINE/configure"
ACTUAL_ENGINE_SHA="$(git -C "$ENGINE" rev-parse HEAD)"
if [ "$ACTUAL_ENGINE_SHA" != "$EXPECTED_ENGINE_SHA" ]; then
    echo "Unexpected QEMU engine revision: $ACTUAL_ENGINE_SHA" >&2
    exit 2
fi

# Stage shared legacy-device support sources and Apple compatibility headers.
# The helper is idempotent; the device config below selects the board to build.
sh "$ROOT/scripts/stage-qemu-iphone4.sh"

# Supply ES extension enum values omitted by Apple's ES 1.1 headers.
python3 "$ROOT/scripts/patch-qemu-ios-gles-enums.py" "$ENGINE/hw/arm/gles-host.c"

# Assert that the staged Apple crypto compatibility headers are actually
# visible to QEMU's quoted include search before starting the expensive build.
test -s "$ENGINE/include/openssl/aes.h"
test -s "$ENGINE/include/openssl/bn.h"
grep -q '#include "openssl/bn.h"' "$ENGINE/hw/arm/ipod_touch_pke.c"

# The iOS SDK provides CommonCrypto, not OpenSSL headers/libraries.
python3 "$ROOT/scripts/patch-qemu-ios-apple-aes.py" "$ENGINE/include/hw/arm/ipod_touch_aes.h"

# Select exactly the requested board. CONFIG_IPOD_TOUCH_1G selects the shared
# S5L8720 peripherals and the S5L8900 original-iPhone board through Kconfig.
mkdir -p "$ENGINE/configs/devices/arm-softmmu"
case "$DEVICE_TARGET" in
    iphone4)
        printf '%s\n' 'CONFIG_IPAD1=y' > "$ENGINE/configs/devices/arm-softmmu/ios.mak"
        ;;
    iphone2g)
        printf '%s\n' 'CONFIG_IPOD_TOUCH_1G=y' > "$ENGINE/configs/devices/arm-softmmu/ios.mak"
        ;;
    *)
        echo "Unsupported device target: $DEVICE_TARGET" >&2
        exit 2
        ;;
esac
grep -q "^CONFIG_.*=y$" "$ENGINE/configs/devices/arm-softmmu/ios.mak"
echo "Selected device config:"
cat "$ENGINE/configs/devices/arm-softmmu/ios.mak"

mkdir -p "$BUILD_ROOT"
if [ ! -f "$DEPS/lib/libglib-2.0.a" ]; then
    archive="$BUILD_ROOT/orchard-ios-deps-arm64.tar.xz"
    curl -fL --retry 3 "$DEPS_URL" -o "$archive"
    echo "$DEPS_SHA  $archive" | shasum -a 256 -c -
    rm -rf "$DEPS"
    mkdir -p "$DEPS"
    tar -xJf "$archive" -C "$DEPS"
    rm -f "$archive"
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
AR="$(xcrun --find ar)"
RANLIB="$(xcrun --find ranlib)"
STRIP="$(xcrun --find strip)"

# The dependency archive records the prefix used when it was built. Relocate
# its .pc files to this runner's temp directory and use the SDK's zlib.
OLD_PREFIX="$(cat "$DEPS/PREFIX")"
python3 - "$DEPS" "$OLD_PREFIX" "$SDK" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
old, sdk = sys.argv[2], sys.argv[3]
for pc in (root / "lib/pkgconfig").glob("*.pc"):
    if pc.is_symlink():
        continue
    text = pc.read_text()
    text = text.replace(old, str(root))
    if pc.name == "zlib.pc":
        lines = [f"prefix={sdk}/usr" if line.startswith("prefix=") else line for line in text.splitlines()]
        text = "\n".join(lines) + "\n"
    pc.write_text(text)
(root / "PREFIX").write_text(str(root) + "\n")
PY

# QEMU's configure script runs natively once to generate config-host.mak and
# its Meson venv. The actual objects are then cross-compiled for iOS ARM64.
# QEMU's Meson coroutine detection deliberately excludes ucontext on Darwin;
# sigaltstack is the supported backend on macOS/iOS. Do not link libucontext.
# The bootstrap configure is a NATIVE macOS build. Keep Homebrew's native
# GLib metadata visible here; pointing pkg-config at the iOS ARM64 archive
# makes configure compare host size_t against the target GLib ABI and fail.
if [ ! -f "$BOOT/config-host.mak" ]; then
    mkdir -p "$BOOT"
    (
        cd "$BOOT"
        "$ENGINE/configure" --target-list=arm-softmmu --disable-docs \
            --enable-slirp --disable-werror --with-devices-arm=ios
    )
fi

# Only the actual iOS cross-build may see the target dependency archive.
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
export PKG_CONFIG_PATH=""
# The .pc files were relocated to the actual dependency prefix above. Setting
# PKG_CONFIG_SYSROOT_DIR here makes pkg-config prepend the iPhoneOS SDK to those
# already-absolute paths (e.g. SDK/Users/runner/...), so Meson cannot find glib.h
# and its GLIB_SIZEOF_SIZE_T check fails. Clang gets the SDK via the cross file.
unset PKG_CONFIG_SYSROOT_DIR
echo "Target GLib: $(pkg-config --modversion glib-2.0)"
echo "Target GLib cflags: $(pkg-config --cflags glib-2.0)"

mkdir -p "$IOS"
CROSS="$IOS/cross-ios-arm64.txt"
cat > "$CROSS" <<EOF
[binaries]
c = 'clang'
cpp = 'clang++'
objc = 'clang'
ar = '$AR'
strip = '$STRIP'
ranlib = '$RANLIB'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-mios-version-min=17.0', '-I$DEPS/include', '-fPIC']
# QEMU's iPhone display bridge calls Apple's CoreMedia/CoreVideo APIs, while
# the upstream iPod H.264 path references VideoToolbox. These frameworks must
# be present on both C and C++ link commands so Meson tests and the final dylib
# resolve the same iOS SDK symbols.
c_link_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-mios-version-min=17.0', '-L$DEPS/lib', '-framework', 'CoreFoundation', '-framework', 'Foundation', '-framework', 'OpenGLES', '-framework', 'IOSurface', '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-framework', 'VideoToolbox']
cpp_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-mios-version-min=17.0', '-I$DEPS/include', '-fPIC']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-mios-version-min=17.0', '-L$DEPS/lib', '-framework', 'CoreFoundation', '-framework', 'Foundation', '-framework', 'OpenGLES', '-framework', 'IOSurface', '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-framework', 'VideoToolbox']
objc_args = ['-arch', 'arm64', '-isysroot', '$SDK', '-mios-version-min=17.0', '-I$DEPS/include', '-fPIC']

[host_machine]
system = 'darwin'
subsystem = 'ios'
kernel = 'xnu'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$DEPS/lib/pkgconfig']
arm-softmmu = 'ios'
EOF

if [ ! -f "$IOS/build.ninja" ]; then
    cp "$BOOT/config-host.mak" "$IOS/config-host.mak"
    (
        cd "$IOS"
        "$BOOT/pyvenv/bin/meson" setup . "$ENGINE" \
            --cross-file="$CROSS" \
            -Dbuildtype=release -Dprefix="$DEPS" \
            -Ddefault_devices=true -Dmodules=disabled -Ddocs=disabled \
            -Dkvm=disabled -Dhvf=disabled -Dwhpx=disabled \
            -Dcocoa=disabled -Dgtk=disabled -Dsdl=disabled -Dcurses=disabled \
            -Dcoreaudio=disabled -Dcurl=disabled -Dtools=disabled \
            -Dlibssh=disabled -Dbzip2=disabled -Dslirp=enabled \
            -Dtcg=enabled -Dtcg_interpreter=true \
            -Dcoroutine_backend=sigaltstack -Dwerror=false
    )
fi

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
ninja -C "$IOS" -j"$JOBS" qemu-system-arm

# Compile QEMU's iOS-specific entry point and frame/input bridge with the same
# generated flags and include paths as system/main.c.
python3 - "$ENGINE" "$IOS" <<'PY'
import json, pathlib, shlex, subprocess, sys
engine, build = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
commands = json.loads((build / "compile_commands.json").read_text())
entry = next((x for x in commands if x["file"].endswith("/system/main.c")), None)
if entry is None:
    raise SystemExit("Could not find QEMU's system/main.c compile command")
base = entry.get("arguments") or shlex.split(entry["command"])
for name in ("qemu-ios-entry", "qemu-ios-ui"):
    source = engine / "contrib/ios-app" / f"{name}.c"
    output = build / f"{name}.o"
    depfile = build / f"{name}.d"
    args = list(base)
    for i, arg in enumerate(args):
        if not arg.startswith("-") and arg.endswith("system/main.c"):
            args[i] = str(source)
        elif arg == "-o" and i + 1 < len(args):
            args[i + 1] = str(output)
        elif arg == "-MF" and i + 1 < len(args):
            args[i + 1] = str(depfile)
    if not any(arg == str(source) for arg in args):
        raise SystemExit(f"Could not replace system/main.c with {source}")
    args.extend(["-I", str(engine / "contrib/ios-app"), "-fPIC"])
    print("Compiling", source)
    subprocess.run(args, cwd=entry["directory"], check=True)
PY

# Relink the emulator's exact object/library set as an embeddable iOS dylib,
# replacing QEMU's command-line main() with qemu_ios_main().
python3 - "$IOS" "$ROOT" <<'PY'
import pathlib, shlex, subprocess, sys
build, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
commands = subprocess.check_output(
    ["ninja", "-C", str(build), "-t", "commands", "qemu-system-arm-unsigned"],
    text=True
).splitlines()
if not commands:
    raise SystemExit("Ninja did not expose the qemu-system-arm-unsigned link command")
args = shlex.split(commands[-1])
entry = build / "qemu-ios-entry.o"
ui = build / "qemu-ios-ui.o"
out = root / "ios/Frameworks/libqemu-arm.dylib"
exports = build / "ios-exports.syms"
exports.write_text("""_qemu_ios_main
_qemu_ios_device_info
_qemu_ios_device_info_at
_qemu_ios_ui_attach
_qemu_ios_ui_frame
_qemu_ios_ui_frame_size
_qemu_ios_ui_touch
_qemu_ios_ui_button
_qemu_ios_ui_ready
_qemu_ios_ui_storage_failed
_qemu_ios_ui_vm_stopped
_qemu_ios_ui_guest_shutdown_confirmed
_qemu_ios_ui_display_sleeping
_qemu_ios_ui_backlight_level
""")
result, skip = [], False
replaced = False
for arg in args:
    if skip:
        skip = False
        continue
    if arg == "-o":
        skip = True
        continue
    if arg in ("-pie", "-Wl,-pie", "-Wl,-no_pie"):
        continue
    if arg.endswith("system/main.c.o"):
        result.extend([str(entry), str(ui)])
        replaced = True
    else:
        result.append(arg)
if not replaced:
    raise SystemExit("Could not replace system/main.c.o in QEMU's link command")
out.parent.mkdir(parents=True, exist_ok=True)
result.extend([
    "-dynamiclib", "-o", str(out),
    f"-Wl,-exported_symbols_list,{exports}",
    "-Wl,-install_name,@rpath/libqemu-arm.dylib",
    "-Wl,-undefined,dynamic_lookup"
])
print("Linking", out)
subprocess.run(result, cwd=build, check=True)
PY

LIB="$ROOT/ios/Frameworks/libqemu-arm.dylib"
test -s "$LIB"
vtool -show-build-version "$LIB"
symbols="$(nm -gU "$LIB")"
for symbol in qemu_ios_main qemu_ios_ui_attach qemu_ios_ui_frame qemu_ios_ui_touch; do
    if ! grep -q " _$symbol$" <<<"$symbols"; then
        echo "Missing exported iOS runtime symbol: $symbol" >&2
        exit 5
    fi
done
file "$LIB"
echo "Built iOS QEMU runtime: $LIB"
