#!/bin/bash
set -e

REPO_URL="https://github.com/SahiK19/agent-installation.git"
INSTALL_DIR="/opt/agent-installation"

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

echo "[1/6] Updating system packages..."
apt update -y
apt install -y git snort python3 python3-pip

echo
echo "[2/6] Downloading installation package from GitHub..."

# Fresh clone every time
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "ERROR: Failed to clone repository!"
    exit 1
fi

SNORT_SRC="$INSTALL_DIR/snort_installation"
CORR_SRC="$INSTALL_DIR/correlator"

echo
echo "[3/6] Installing Snort configuration..."

if [ ! -f "$SNORT_SRC/snort.conf" ]; then
    echo "ERROR: Snort config not found in repo!"
    exit 1
fi

# Clean default apt-installed snort config
rm -f /etc/snort/snort.conf
rm -rf /etc/snort/rules
mkdir -p /etc/snort/rules

cp "$SNORT_SRC/snort.conf" /etc/snort/
cp -r "$SNORT_SRC/rules/"* /etc/snort/rules/ 2>/dev/null || true

chown -R snort:snort /etc/snort
chmod -R 644 /etc/snort/rules/* || true

echo "[OK] Snort configuration installed."

echo
echo "[4/6] Installing correlator script..."

if [ ! -f "$CORR_SRC/correlate.py" ]; then
    echo "ERROR: correlate.py missing in repo!"
    exit 1
fi

cp "$CORR_SRC/correlate.py" /usr/local/bin/correlate.py
chmod +x /usr/local/bin/correlate.py

echo "[OK] correlate.py installed."

echo
echo "[5/6] Installing correlator systemd service..."

if [ ! -f "$CORR_SRC/correlator.service" ]; then
    echo "ERROR: correlator.service missing in repo!"
    exit 1
fi

cp "$CORR_SRC/correlator.service" /etc/systemd/system/correlator.service

systemctl daemon-reload
systemctl enable correlator.service
systemctl restart correlator.service

echo "[OK] correlator.service enabled and started."

echo
echo "[6/6] Verifying service status..."
systemctl status correlator.service --no-pager || true

echo
echo "=============================================="
echo "   ✔ INSTALLATION COMPLETED SUCCESSFULLY"
echo "=============================================="
