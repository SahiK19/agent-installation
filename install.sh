#!/bin/bash

set -e

echo "================================================="
echo "     AGENT INSTALLATION PACKAGE - FULL INSTALL   "
echo "================================================="

# Base directory of the git repo
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[1/8] Updating system packages..."
apt update -y

echo "[2/8] Installing dependencies..."
apt install -y snort python3 python3-pip

echo "[3/8] Replacing Snort config & rules..."

# Ensure Snort folder exists
mkdir -p /etc/snort/rules

# Remove default config
rm -f /etc/snort/snort.conf
rm -rf /etc/snort/rules/*

# Copy your custom config + rules
cp "$BASE_DIR/snort_installation/snort.conf" /etc/snort/
cp -r "$BASE_DIR/snort_installation/rules/"* /etc/snort/rules/

# Permissions
chown -R snort:snort /etc/snort/snort.conf
chown -R snort:snort /etc/snort/rules
chmod 644 /etc/snort/snort.conf
chmod -R 644 /etc/snort/rules/*

echo "[4/8] Verifying Snort installation..."
snort -T -c /etc/snort/snort.conf || { echo "Snort configuration test FAILED!"; exit 1; }

echo "[5/8] Installing correlator script..."
cp "$BASE_DIR/correlator/correlate.py" /usr/local/bin/correlate.py
chmod +x /usr/local/bin/correlate.py

echo "[6/8] Installing correlator service..."
cp "$BASE_DIR/correlator/correlator.service" /etc/systemd/system/correlator.service

echo "[7/8] Enabling correlator service..."
systemctl daemon-reload
systemctl enable correlator.service
systemctl restart correlator.service

echo "[8/8] Done! Checking correlator status..."
systemctl status correlator.service --no-pager

echo "================================================="
echo " INSTALLATION COMPLETE!"
echo " Snort running with your custom configuration."
echo " Correlator service is active."
echo "================================================="

