#!/usr/bin/env bash
# proxmox-redfish installation script for Proxmox VE.
#
# Installs the proxmox-redfish daemon which exposes a Redfish API
# for Proxmox VMs, enabling Metal3/Ironic to manage them as if they
# were bare metal servers with BMC.
#
# Project: https://github.com/v1k0d3n/proxmox-redfish
# License: MIT
#
# Prerequisites:
#   - Proxmox VE 7.0+
#   - Python 3.8+
#   - Network access to Proxmox API
#
# Usage:
#   ssh root@<proxmox-ip> 'bash -s' < install.sh
#
# After installation, the daemon will be available at:
#   https://<proxmox-ip>:8443/redfish/v1/
#
# Default credentials: admin / admin (change in /etc/proxmox-redfish/params.env)

set -euo pipefail

INSTALL_DIR="/opt/proxmox-redfish"
VENV_DIR="${INSTALL_DIR}/venv"
SERVICE_FILE="/etc/systemd/system/proxmox-redfish.service"
CONFIG_DIR="/etc/proxmox-redfish"

echo "=== proxmox-redfish installation ==="

# Create directories
mkdir -p "${INSTALL_DIR}"
mkdir -p "${CONFIG_DIR}"

# Clone the repository
if [ ! -d "${INSTALL_DIR}/proxmox-redfish" ]; then
    echo "Cloning proxmox-redfish..."
    apt-get update -qq && apt-get install -y -qq git
    git clone https://github.com/v1k0d3n/proxmox-redfish.git "${INSTALL_DIR}/proxmox-redfish"
fi

# Create Python virtual environment
echo "Creating Python venv..."
python3 -m venv "${VENV_DIR}"

# Install pip in the venv
echo "Installing pip..."
"${VENV_DIR}/bin/python" -m ensurepip --upgrade

# Install dependencies
echo "Installing Python dependencies..."
cd "${INSTALL_DIR}/proxmox-redfish"
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r requirements.txt 2>/dev/null || {
    # If no requirements.txt, install the package directly
    "${VENV_DIR}/bin/pip" install -e .
}

# Create default config
if [ ! -f "${CONFIG_DIR}/params.env" ]; then
    echo "Creating default config..."
    cat > "${CONFIG_DIR}/params.env" << 'EOF'
# proxmox-redfish configuration
# https://github.com/v1k0d3n/proxmox-redfish

# Proxmox API settings
PROXMOX_HOST=127.0.0.1
PROXMOX_PORT=8006
PROXMOX_USER=root@pam
PROXMOX_PASSWORD=
PROXMOX_VERIFY_SSL=false

# Redfish API settings
REDFISH_HOST=0.0.0.0
REDFISH_PORT=8443
REDFISH_USER=admin
REDFISH_PASS=admin

# SSL settings
USE_SSL=true
SSL_CERT=
SSL_KEY=
EOF
    echo "Config created at ${CONFIG_DIR}/params.env"
    echo ">>> Edit ${CONFIG_DIR}/params.env to set your Proxmox credentials <<<"
fi

# Create systemd service
echo "Creating systemd service..."
cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Proxmox Redfish API Daemon
After=network.target pve-cluster.service
Wants=network.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_DIR}/params.env
WorkingDirectory=${INSTALL_DIR}/proxmox-redfish
ExecStart=${VENV_DIR}/bin/python -m proxmox_redfish.main
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
echo "Enabling and starting service..."
systemctl daemon-reload
systemctl enable proxmox-redfish
systemctl restart proxmox-redfish

# Wait for the service to start
sleep 2
if systemctl is-active --quiet proxmox-redfish; then
    echo ""
    echo "=== Installation successful ==="
    echo "proxmox-redfish is running at https://$(hostname -I | awk '{print $1}'):8443"
    echo "Default credentials: admin / admin"
    echo "Config: ${CONFIG_DIR}/params.env"
    echo ""
    echo "Test with:"
    echo "  curl -k -u admin:admin https://localhost:8443/redfish/v1/"
else
    echo "=== Installation failed ==="
    echo "Check logs: journalctl -u proxmox-redfish -f"
    exit 1
fi
