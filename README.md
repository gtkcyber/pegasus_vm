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

**Status:** the arm64 image builds and is verified end-to-end (XFCE auto-login
+ working JupyterLab for the `student` user). The amd64 image is built on a
native x86 runner via the GitHub Actions workflow.

## For students — starting the VM

You were given **one VM file** for your computer. Pick your platform:

### Apple Silicon Mac (M1/M2/M3/M4) — file ends in `.qcow2`

1. Install [UTM](https://mac.getutm.app) (free): `brew install --cask utm`, or
   download it from the website.
2. Open UTM → **Create a New Virtual Machine** → **Virtualize** → **Linux**.
3. Under "Boot ISO Image" leave it empty / skip, finish the wizard, then open
   the new VM's **Settings → Drives**, delete the empty drive, and **Import** the
   `course-arm64.qcow2` file you were given.
4. Click the **▶︎ Play** button to start. (To stop: the desktop menu →
   **Log Out → Shut Down**, or close the UTM window.)

### Windows, Linux, or Intel Mac — file ends in `.ova`

1. Install [VirtualBox](https://www.virtualbox.org) (free).
2. **File → Import Appliance…**, select `course-amd64.ova`, click through, and
   **Import**.
3. Select the imported VM and click **Start**. (To stop: the desktop menu →
   **Log Out → Shut Down**, or close the window and choose "Send shutdown signal".)

### Once it boots (either platform)

The VM **auto-logs in** to the desktop — no password needed. (If anything ever
asks: the login is `student` / `student`.) Double-click the **Course JupyterLab**
icon on the desktop; a browser window opens with JupyterLab. In a notebook,
choose the **Course (Python 3.12)** kernel. Your notebooks live in the
`notebooks` folder in your home directory.

## The one thing to understand first

Packer boots a real guest to build the image, so each architecture needs a host
of the same architecture to build at native speed:

| Build host        | arm64 image          | amd64 image          |
|-------------------|----------------------|----------------------|
| Apple Silicon Mac | fast (`hvf`)         | slow (`none` / TCG)  |
| x86 Linux / PC    | slow (`none` / TCG)  | fast (`kvm`)         |

The template and provisioning script are shared; only the build host and the
`accel_*` variables change. Build one target at a time with `-only`. For both
at native speed, build **arm64 on the Mac** (`make arm64`, fast with `hvf`) and
**amd64 in CI** — the GitHub Actions workflow (`.github/workflows/build.yml`)
builds amd64 on an x86 runner with KVM in ~25 min and uploads the artifact.
(arm64 is not built in CI: GitHub's hosted arm64 runners have no `/dev/kvm`, so
only TCG emulation would be available there — slow and pointless when you have
an Apple Silicon Mac.)

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

## Test the built image locally (Apple Silicon)

To boot the arm64 image in a native window straight from QEMU (no UTM needed),
after a successful `make arm64`:

```
./scripts/run-arm64.sh        # opens the VM in a window, auto-logs into XFCE
```

It boots from `output/arm64/course-arm64.qcow2` using a writable copy of the
UEFI varstore Packer produced. **Start** the VM by running the script; **stop**
it by shutting down from inside (Log Out → Shut Down), running `sudo poweroff`
in a guest terminal, or just closing the QEMU window.

If the window goes black with "Display output is not active", that's just the
desktop's screen blanking after idle — move the mouse or press a key to wake it.

The default login is `student` / `student` (auto-login is on, so you land on the
desktop). Double-click **Course JupyterLab** to start the server.

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
