#!/usr/bin/env bash
#
# provision-course-vm.sh
# -----------------------------------------------------------------------------
# Turn a minimal Ubuntu 26.04 LTS install (amd64 OR arm64) into a lightweight
# cybersecurity course VM: XFCE desktop + a single uv-managed JupyterLab env.
#
# Architecture-agnostic: apt and the uv installer both resolve the correct
# binaries for whatever arch this runs on. Used as the single source of truth
# by the Packer build for both targets.
# -----------------------------------------------------------------------------
set -euo pipefail

#############################################
# Config -- edit these per course
#############################################
STUDENT_USER="${STUDENT_USER:-${SUDO_USER:-student}}"
STUDENT_PASS="${STUDENT_PASS:-student}"
ENV_DIR="/opt/course-env"
PY_VERSION="${PY_VERSION:-3.12}"
KERNEL_NAME="course"
KERNEL_DISPLAY="Course (Python ${PY_VERSION})"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
AUTO_LOGIN="${AUTO_LOGIN:-true}"
NOTEBOOK_DIR_NAME="notebooks"

# Course Python packages. All ship amd64 AND aarch64 wheels (fast, no compile).
PKGS=(
  jupyterlab
  ipykernel
  numpy
  pandas
  scipy
  scikit-learn
  matplotlib
  seaborn
  pyod
  requests
)

#############################################
# Pre-flight
#############################################
if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive

echo "==> Target user: ${STUDENT_USER} (arch: $(dpkg --print-architecture))"
if ! id -u "${STUDENT_USER}" >/dev/null 2>&1; then
  echo "==> Creating user ${STUDENT_USER}"
  adduser --disabled-password --gecos "" "${STUDENT_USER}"
  echo "${STUDENT_USER}:${STUDENT_PASS}" | chpasswd
  usermod -aG sudo "${STUDENT_USER}"
fi
STUDENT_HOME="$(getent passwd "${STUDENT_USER}" | cut -d: -f6)"

#############################################
# Lightweight XFCE desktop + browser + VM guest agents
#############################################
echo "==> Installing XFCE desktop, browser, and guest agents"
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  xubuntu-desktop-minimal \
  firefox \
  spice-vdagent \
  qemu-guest-agent \
  curl ca-certificates git
systemctl set-default graphical.target

#############################################
# Optional auto-login into XFCE
#############################################
if [[ "${AUTO_LOGIN}" == "true" ]]; then
  echo "==> Enabling LightDM auto-login for ${STUDENT_USER}"
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat > /etc/lightdm/lightdm.conf.d/50-course-autologin.conf <<EOF
[Seat:*]
autologin-user=${STUDENT_USER}
autologin-session=xubuntu
EOF
fi

#############################################
# uv (system-wide) + one shared, pinned course env
#############################################
echo "==> Installing uv to /usr/local/bin"
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

echo "==> Creating shared course env at ${ENV_DIR} (Python ${PY_VERSION})"
/usr/local/bin/uv venv --python "${PY_VERSION}" "${ENV_DIR}"
/usr/local/bin/uv pip install --python "${ENV_DIR}/bin/python" --upgrade pip
/usr/local/bin/uv pip install --python "${ENV_DIR}/bin/python" "${PKGS[@]}"

echo "==> Registering Jupyter kernel: ${KERNEL_NAME}"
"${ENV_DIR}/bin/python" -m ipykernel install \
  --name "${KERNEL_NAME}" --display-name "${KERNEL_DISPLAY}"
chown -R "${STUDENT_USER}:${STUDENT_USER}" "${ENV_DIR}"

#############################################
# Launcher: start-jupyter + desktop icon
#############################################
echo "==> Installing JupyterLab launcher"
NOTEBOOK_DIR="${STUDENT_HOME}/${NOTEBOOK_DIR_NAME}"
install -d -o "${STUDENT_USER}" -g "${STUDENT_USER}" "${NOTEBOOK_DIR}"

cat > /usr/local/bin/start-jupyter <<EOF
#!/usr/bin/env bash
exec ${ENV_DIR}/bin/jupyter lab \\
  --port=${JUPYTER_PORT} \\
  --notebook-dir="\${HOME}/${NOTEBOOK_DIR_NAME}"
EOF
chmod +x /usr/local/bin/start-jupyter

DESKTOP_ENTRY="/usr/share/applications/course-jupyterlab.desktop"
cat > "${DESKTOP_ENTRY}" <<EOF
[Desktop Entry]
Type=Application
Name=Course JupyterLab
Comment=Start the course JupyterLab server
Exec=/usr/local/bin/start-jupyter
Icon=accessories-text-editor
Terminal=true
Categories=Development;Education;
EOF

install -d -o "${STUDENT_USER}" -g "${STUDENT_USER}" "${STUDENT_HOME}/Desktop"
cp "${DESKTOP_ENTRY}" "${STUDENT_HOME}/Desktop/course-jupyterlab.desktop"
chown "${STUDENT_USER}:${STUDENT_USER}" "${STUDENT_HOME}/Desktop/course-jupyterlab.desktop"
chmod +x "${STUDENT_HOME}/Desktop/course-jupyterlab.desktop"

echo "==> Provisioning complete on $(dpkg --print-architecture)."
