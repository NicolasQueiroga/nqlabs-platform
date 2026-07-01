#!/usr/bin/env bash
# proxmox-redfish installation script for Proxmox VE.
#
# Installs the proxmox-redfish daemon which exposes a Redfish API
# for Proxmox VMs, enabling Metal3/Ironic to manage them as if they
# were bare metal servers with BMC.
#
# Project: https://github.com/v1k0d3n/proxmox-redfish
# License: Apache-2.0
#
# Prerequisites:
#   - Proxmox VE 7.0+
#   - Python 3.8+
#   - Root access to Proxmox host
#
# Usage:
#   ssh root@<proxmox-ip> 'bash -s' < install.sh
#
# After installation, the daemon will be available at:
#   https://<proxmox-ip>:8443/redfish/v1/
#
# Default credentials: admin / admin (set in params.env)
#
# The script is idempotent — it can be run multiple times safely.

set -euo pipefail

INSTALL_DIR="/opt/proxmox-redfish"
CONFIG_DIR="${INSTALL_DIR}/config"
SSL_DIR="${CONFIG_DIR}/ssl"
SERVICE_FILE="/etc/systemd/system/proxmox-redfish.service"

echo "=== proxmox-redfish installation ==="

# Install system dependencies
echo "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv git jq openssl curl

# Clone or update the repository
if [ -d "${INSTALL_DIR}/.git" ]; then
    echo "Updating existing repository..."
    cd "${INSTALL_DIR}"
    git pull --ff-only
else
    echo "Cloning proxmox-redfish..."
    rm -rf "${INSTALL_DIR}"
    git clone https://github.com/v1k0d3n/proxmox-redfish.git "${INSTALL_DIR}"
fi

# Create Python virtual environment
echo "Creating Python venv..."
cd "${INSTALL_DIR}"
python3 -m venv venv

# Install the package
echo "Installing proxmox-redfish package..."
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -e .

# Create directories
mkdir -p "${CONFIG_DIR}" "${SSL_DIR}"

# Generate SSL certificates (self-signed for lab)
if [ ! -f "${SSL_DIR}/server.key" ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout "${SSL_DIR}/server.key" \
        -out "${SSL_DIR}/server.crt" \
        -days 365 -nodes \
        -subj "/CN=$(hostname)"
    chmod 600 "${SSL_DIR}/server.key"
    chmod 644 "${SSL_DIR}/server.crt"
fi

# Create default config
if [ ! -f "${CONFIG_DIR}/params.env" ]; then
    echo "Creating default config..."
    cat > "${CONFIG_DIR}/params.env" << 'EOF'
# proxmox-redfish configuration
# https://github.com/v1k0d3n/proxmox-redfish

# Proxmox Configuration
PROXMOX_HOST=127.0.0.1
PROXMOX_USER=root@pam
PROXMOX_PASSWORD=
PROXMOX_API_PORT=8006
PROXMOX_NODE=
PROXMOX_ISO_STORAGE=local

# SSL Configuration
SSL_CERT_FILE=/opt/proxmox-redfish/config/ssl/server.crt
SSL_KEY_FILE=/opt/proxmox-redfish/config/ssl/server.key

# Logging Configuration
REDFISH_LOG_LEVEL=INFO
REDFISH_LOGGING_ENABLED=true

# SSL Verification (for Proxmox API)
VERIFY_SSL=false
EOF
    echo ""
    echo ">>> IMPORTANT: Edit ${CONFIG_DIR}/params.env to set:"
    echo "    - PROXMOX_PASSWORD (your Proxmox root password)"
    echo "    - PROXMOX_NODE (your Proxmox hostname)"
    echo ""
fi

# Create systemd service
echo "Creating systemd service..."
cat > "${SERVICE_FILE}" << 'EOF'
[Unit]
Description=Proxmox Redfish Daemon
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/proxmox-redfish
EnvironmentFile=/opt/proxmox-redfish/config/params.env
ExecStart=/opt/proxmox-redfish/venv/bin/python /opt/proxmox-redfish/src/proxmox_redfish/proxmox_redfish.py --port 8443
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${SERVICE_FILE}"

# Enable and start the service
echo "Enabling and starting service..."
systemctl daemon-reload
systemctl enable proxmox-redfish

# Check if config has password set
if grep -q "^PROXMOX_PASSWORD=$" "${CONFIG_DIR}/params.env"; then
    echo ""
    echo "=== WARNING: Proxmox password not set ==="
    echo "Edit ${CONFIG_DIR}/params.env and set PROXMOX_PASSWORD, then run:"
    echo "  systemctl restart proxmox-redfish"
    echo ""
else
    systemctl restart proxmox-redfish
    sleep 2
    if systemctl is-active --quiet proxmox-redfish; then
        echo ""
        echo "=== Installation successful ==="
        echo "proxmox-redfish is running at https://$(hostname -I | awk '{print $1}'):8443"
        echo "Default credentials: admin / admin"
        echo ""
        echo "Test with:"
        echo "  curl -k -u admin:admin https://localhost:8443/redfish/v1/"
    else
        echo "=== Installation failed ==="
        echo "Check logs: journalctl -u proxmox-redfish -f"
        exit 1
    fi
fi
