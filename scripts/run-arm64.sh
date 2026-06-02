#!/usr/bin/env bash
#
# run-arm64.sh -- boot the built arm64 course VM locally on an Apple Silicon Mac
# in a native window (QEMU + hvf). For quick local testing of the image; the
# distribution path for students is still UTM (see README).
#
#   ./scripts/run-arm64.sh            # start the VM in a window
#
# Stop it by shutting down from inside the desktop (Log Out -> Shut Down), or
# run `sudo poweroff` in a guest terminal, or just close the QEMU window.
# -----------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."

QCOW="output/arm64/course-arm64.qcow2"
EDK_CODE="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
# Writable UEFI varstore. Reuse the one Packer produced (it already has the
# "ubuntu" boot entry) by copying it to a per-run, writable file.
VARS="output/arm64/run-efivars.fd"

[[ -f "$QCOW" ]] || { echo "missing $QCOW -- run 'make arm64' first" >&2; exit 1; }
[[ -f "$VARS" ]] || cp "output/arm64/efivars.fd" "$VARS"

exec qemu-system-aarch64 \
  -machine virt,accel=hvf -cpu host -smp 2 -m 4096 \
  -drive "file=${EDK_CODE},if=pflash,unit=0,format=raw,readonly=on" \
  -drive "file=${VARS},if=pflash,unit=1,format=raw" \
  -drive "file=${QCOW},if=virtio,format=qcow2" \
  -device virtio-gpu-pci -device qemu-xhci -device usb-kbd -device usb-tablet \
  -device virtio-net,netdev=n0 -netdev user,id=n0 \
  -display cocoa
