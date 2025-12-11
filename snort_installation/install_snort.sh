#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

BASE_DIR="/home/agent_installation_package"
SNORT_DIR="$BASE_DIR/snort_installation"
CORR_DIR="$BASE_DIR/correlator"

echo "=== Updating system and installing Snort + Python3 ==="
sudo apt update
sudo apt install -y snort python3 python3-pip

echo
echo "=== Snort version installed ==="
snort -V || { echo "Snort not installed correctly"; exit 1; }

echo
echo "=== Preparing /etc/snort directory ==="
# Ensure base config directory exists (apt should create this, but just in case)
sudo mkdir -p /etc/snort

echo
echo "=== Removing default snort.conf and rules installed by apt ==="
if [ -f /etc/snort/snort.conf ]; then
    echo " - Removing /etc/snort/snort.conf"
    sudo rm -f /etc/snort/snort.conf
else
    echo " - No default /etc/snort/snort.conf found (already removed?)"
fi

if [ -d /etc/snort/rules ]; then
    echo " - Removing /etc/snort/rules directory"
    sudo rm -rf /etc/snort/rules
else
    echo " - No default /etc/snort/rules directory found (already removed?)"
fi

echo
echo "=== Copying custom Snort configuration from $SNORT_DIR ==="
if [ ! -f "$SNORT_DIR/snort.conf" ]; then
    echo "ERROR: $SNORT_DIR/snort.conf not found"
    exit 1
fi

sudo cp "$SNORT_DIR/snort.conf" /etc/snort/

echo " - Ensuring /etc/snort/rules exists"
sudo mkdir -p /etc/snort/rules

if [ -d "$SNORT_DIR/rules" ]; then
    echo " - Copying custom rules to /etc/snort/rules/"
    sudo cp -r "$SNORT_DIR/rules/"* /etc/snort/rules/ || true
else
    echo "WARNING: $SNORT_DIR/rules directory not found, skipping rules copy"
fi

echo
echo "=== Setting permissions for Snort configuration and rules ==="
if [ -f /etc/snort/snort.conf ]; then
    sudo chown snort:snort /etc/snort/snort.conf
    sudo chmod 644 /etc/snort/snort.conf
fi

if [ -d /etc/snort/rules ]; then
    sudo chown -R snort:snort /etc/snort/rules
    sudo chmod -R 644 /etc/snort/rules/* || true
fi

echo
echo "=== Setting up correlator (Python3 script + systemd service) ==="

# Ensure correlator files exist
if [ ! -f "$CORR_DIR/correlate.py" ]; then
    echo "ERROR: $CORR_DIR/correlate.py not found"
    exit 1
fi

if [ ! -f "$CORR_DIR/correlator.service" ]; then
    echo "ERROR: $CORR_DIR/correlator.service not found"
    exit 1
fi

echo " - Copying correlate.py to /usr/local/bin/"
sudo cp "$CORR_DIR/correlate.py" /usr/local/bin/correlate.py
sudo chmod +x /usr/local/bin/correlate.py

echo " - Installing correlator.service to /etc/systemd/system/"
sudo cp "$CORR_DIR/correlator.service" /etc/systemd/system/correlator.service

echo
echo "=== Reloading systemd and enabling correlator.service ==="
sudo systemctl daemon-reload
sudo systemctl enable correlator.service

echo "=== Starting correlator.service ==="
sudo systemctl restart correlator.service

echo
echo "=== Verifying correlator.service status ==="
sudo systemctl status correlator.service --no-pager || true

echo
echo "✅ Installation completed successfully."
