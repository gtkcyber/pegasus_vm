# Cybersecurity course VM (Packer, dual-architecture)

Builds a lightweight Ubuntu 26.04 LTS course VM (XFCE + a uv-managed JupyterLab
environment) for both Apple Silicon (arm64) and Intel/AMD (amd64) students from
one source of truth.

* `scripts/provision-course-vm.sh` defines everything inside the image. Edit the
  `PKGS` list there to change the course Python stack, then rebuild.
* `ubuntu-course.pkr.hcl` defines two QEMU sources (amd64, arm64) that share that
  one provisioning step.
* Outputs: `output/arm64/course-arm64.qcow2` (for UTM) and
  `output/amd64/course-amd64.qcow2` plus `course-amd64.ova` (for VirtualBox /
  VMware Fusion).

## The one thing to understand first

Packer boots a real guest to build the image, so each architecture needs a host
of the same architecture to build at native speed:

| Build host        | arm64 image          | amd64 image          |
|-------------------|----------------------|----------------------|
| Apple Silicon Mac | fast (`hvf`)         | slow (`none` / TCG)  |
| x86 Linux / PC    | slow (`none` / TCG)  | fast (`kvm`)         |

The template and provisioning script are shared; only the build host and the
`accel_*` variables change. Build one target at a time with `-only`. For both
at native speed, build arm64 on the Mac and amd64 on any x86 box (or use the CI
workflow, which puts each arch on a matching runner).

## Prerequisites (macOS build host)

```
brew install packer qemu
ls "$(brew --prefix qemu)/share/qemu" | grep -i edk2   # confirm firmware paths
```

Set the firmware paths and accelerators in `variables.auto.pkrvars.hcl` to match
your host (defaults assume Apple Silicon + Homebrew).

## Build

```
make arm64     # course-arm64.qcow2          (fast on Apple Silicon)
make amd64     # course-amd64.qcow2 + .ova    (fast on x86)
```

`make validate` checks the template first; `make clean` wipes `output/`.

The ISO checksum variables use Packer's `file:` form, so they read the live
`SHA256SUMS` from the Ubuntu mirror. If a build fails at the checksum step,
confirm the exact ISO filename on the release page and update `iso_url_*`.

## Distribute and import

**arm64 / UTM:** ship `course-arm64.qcow2`. In UTM: New VM, Virtualize, Linux,
select Apple Virtualization (or QEMU), and import the qcow2 as the drive.

**amd64 / VirtualBox or Fusion:** ship `course-amd64.ova`. Import via
File > Import Appliance. If a specific VirtualBox version rejects the OVA, the
`course-amd64.qcow2` (or the VMDK inside the OVA) can be attached to a new VM
manually as a fallback.

Default login is `student` / `student`, with auto-login into XFCE. Change
`ssh_username` / `ssh_password` (and the hash in `http/user-data`) before
distributing if that matters for your deployment.

## Inside the VM

Double-click "Course JupyterLab" on the desktop, or run `start-jupyter`. The
shared env lives at `/opt/course-env`; in a notebook, pick the
"Course (Python 3.12)" kernel. Notebooks live in `~/notebooks`.

## Updating the image

Edit `scripts/provision-course-vm.sh` (usually just `PKGS`), then rerun
`make arm64` / `make amd64`. The base install is untouched; only the
provisioning layer changes, so iteration is quick.
