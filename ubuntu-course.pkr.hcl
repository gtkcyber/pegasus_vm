# =============================================================================
# ubuntu-course.pkr.hcl
# Dual-architecture Packer build for the cybersecurity course VM.
#
#   * One provisioning script (scripts/provision-course-vm.sh) is the single
#     source of truth for what goes inside the image.
#   * Two QEMU sources (amd64, arm64) share that one build block.
#   * Output: qcow2 per arch. amd64 is additionally wrapped into an OVA for
#     VirtualBox / VMware Fusion; arm64 qcow2 imports directly into UTM.
#
# Build one target at a time, on matching hardware where possible:
#   packer init .
#   packer build -only='qemu.arm64' .     # fast on Apple Silicon (hvf)
#   packer build -only='qemu.amd64' .     # fast on x86 (kvm); slow on Mac (tcg)
# =============================================================================

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables. Override in variables.auto.pkrvars.hcl or with -var.
# -----------------------------------------------------------------------------
variable "iso_url_amd64" {
  type    = string
  default = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
}
variable "iso_checksum_amd64" {
  type    = string
  default = "file:https://releases.ubuntu.com/26.04/SHA256SUMS"
}
variable "iso_url_arm64" {
  type    = string
  default = "https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso"
}
variable "iso_checksum_arm64" {
  type    = string
  default = "file:https://cdimage.ubuntu.com/releases/26.04/release/SHA256SUMS"
}

# Accelerator per arch. Set to the hardware-native option for your build host
# and "none" (TCG software emulation, slow) for the off-architecture target.
#   Apple Silicon Mac:  accel_arm64 = "hvf",  accel_amd64 = "none"
#   x86 Linux host:     accel_amd64 = "kvm",  accel_arm64 = "none"
variable "accel_arm64" {
  type    = string
  default = "hvf"
}
variable "accel_amd64" {
  type    = string
  default = "none"
}

# UEFI firmware for the arm64 guest (arm64 has no BIOS). Defaults assume QEMU
# installed via Homebrew on Apple Silicon. Adjust for Intel Mac / Linux.
variable "edk2_arm64_code" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
}
variable "edk2_arm64_vars" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
}

variable "disk_size" {
  type    = string
  default = "30G"
}
variable "memory" {
  type    = number
  default = 4096
}
variable "cpus" {
  type    = number
  default = 2
}
variable "ssh_username" {
  type    = string
  default = "student"
}
variable "ssh_password" {
  type      = string
  default   = "student"
  sensitive = true
}

# -----------------------------------------------------------------------------
# Locals: per-arch QEMU settings and a shared autoinstall boot_command.
# -----------------------------------------------------------------------------
locals {
  # Drop to the GRUB command line ("c"), point the kernel at the NoCloud
  # autoinstall seed served from http/, then boot. Works under both BIOS and
  # UEFI GRUB, so a single boot_command covers both arches.
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  # With TCG (accel = none) you cannot use -cpu host; use the generic "max".
  cpu_amd64 = var.accel_amd64 == "none" ? "max" : "host"
  cpu_arm64 = var.accel_arm64 == "none" ? "max" : "host"
}

# -----------------------------------------------------------------------------
# amd64 source -> qcow2 (later wrapped into an OVA)
# -----------------------------------------------------------------------------
source "qemu" "amd64" {
  iso_url      = var.iso_url_amd64
  iso_checksum = var.iso_checksum_amd64

  qemu_binary  = "qemu-system-x86_64"
  machine_type = "q35"
  accelerator  = var.accel_amd64
  cpus         = var.cpus
  memory       = var.memory
  disk_size    = var.disk_size

  format           = "qcow2"
  output_directory = "output/amd64"
  vm_name          = "course-amd64.qcow2"

  headless       = true
  http_directory = "http"
  boot_wait      = "5s"
  boot_command   = local.boot_command

  communicator     = "ssh"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "45m"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S -E poweroff"

  qemuargs = [
    ["-cpu", local.cpu_amd64]
  ]
}

# -----------------------------------------------------------------------------
# arm64 source -> qcow2 (imports directly into UTM)
# -----------------------------------------------------------------------------
source "qemu" "arm64" {
  iso_url      = var.iso_url_arm64
  iso_checksum = var.iso_checksum_arm64

  qemu_binary  = "qemu-system-aarch64"
  machine_type = "virt"
  accelerator  = var.accel_arm64
  cpus         = var.cpus
  memory       = var.memory
  disk_size    = var.disk_size

  # arm64 boots via UEFI (pflash), no BIOS.
  efi_boot          = true
  efi_firmware_code = var.edk2_arm64_code
  efi_firmware_vars = var.edk2_arm64_vars

  format           = "qcow2"
  output_directory = "output/arm64"
  vm_name          = "course-arm64.qcow2"

  headless       = true
  http_directory = "http"
  boot_wait      = "5s"
  boot_command   = local.boot_command

  communicator     = "ssh"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "45m"
  shutdown_command = "echo '${var.ssh_password}' | sudo -S -E poweroff"

  qemuargs = [
    ["-cpu", local.cpu_arm64]
  ]
}

# -----------------------------------------------------------------------------
# Shared build: same provisioning script runs in both images.
# -----------------------------------------------------------------------------
build {
  name    = "course"
  sources = ["source.qemu.amd64", "source.qemu.arm64"]

  # Single source of truth. Runs as root via sudo; the desktop, uv, JupyterLab
  # env, kernel, and launcher all come from here.
  provisioner "shell" {
    script           = "scripts/provision-course-vm.sh"
    environment_vars = ["STUDENT_USER=${var.ssh_username}", "AUTO_LOGIN=true"]
    execute_command  = "echo '${var.ssh_password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    expect_disconnect = true
  }

  # Wrap only the amd64 qcow2 into an OVA for VirtualBox / Fusion.
  post-processor "shell-local" {
    only   = ["qemu.amd64"]
    inline = ["bash scripts/make-ova.sh output/amd64/course-amd64.qcow2 output/amd64/course-amd64.ova ${var.memory} ${var.cpus}"]
  }

  post-processor "manifest" {
    output     = "output/manifest.json"
    strip_path = true
  }
}
