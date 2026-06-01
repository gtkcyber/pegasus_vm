# Edit these for your build host, then `packer build` picks them up automatically.
#
# --- Apple Silicon Mac (build arm64 fast, amd64 emulated/slow) ---
accel_arm64 = "hvf"
accel_amd64 = "none"

# --- x86 Linux host (build amd64 fast, arm64 emulated/slow): swap to ---
# accel_amd64 = "kvm"
# accel_arm64 = "none"

# QEMU UEFI firmware for the arm64 guest. Find your paths with:
#   ls "$(brew --prefix qemu)/share/qemu" | grep -i edk2     # macOS / Homebrew
#   ls /usr/share/AAVMF /usr/share/qemu                       # Debian/Ubuntu host
edk2_arm64_code = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
edk2_arm64_vars = "/opt/homebrew/share/qemu/edk2-arm-vars.fd"

# Resize the guests here if your courseware needs more headroom.
disk_size = "30G"
memory    = 4096
cpus      = 2

# Default login baked into the image. Change before distributing if you care.
ssh_username = "student"
ssh_password = "student"
