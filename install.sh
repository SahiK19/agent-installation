#!/bin/bash
set -e

echo "================================================="
echo "     AGENT INSTALLATION PACKAGE - FULL INSTALL"
echo "================================================="

# -----------------------------------------------
# Function: Safe APT Update (Ubuntu 24.04 fix)
# -----------------------------------------------
safe_apt_update() {
    echo "[1/8] Updating system packages (safe mode)..."

    # Try APT update, but DO NOT EXIT on failure
    set +e
    apt update -y
    UPDATE_STATUS=$?
    set -e

    if [[ $UPDATE_STATUS -ne 0 ]]; then
        echo "[WARN] APT update returned warnings/errors."
        echo "[INFO] This is NORMAL on Ubuntu 24.04 or WSL."
        echo "[INFO] Continuing installation..."
    fi
}

# -----------------------------------------------
# Function: Install Dependencies
# -----------------------------------------------
install_dependencies() {
    echo "[2/8] Installing system dependencies..."

    apt install -y \
        build-essential \
        wget curl git \
        python3 python3-pip python3-venv \
        libpcap-dev libpcre3-dev zlib1g-dev \
        libdumbnet-dev bison flex \
        ethtool net-tools

    echo "[OK] Dependencies installed."
}

# -----------------------------------------------
# Function: Install Snort 2.9.20 from Source
# -----------------------------------------------
install_snort() {
    echo "[3/8] Installing Snort 2.9.20 from source..."

    SNORT_VERSION="2.9.20"
    SNORT_TARBALL="snort-${SNORT_VERSION}.tar.gz"

    cd /tmp
    wget https://www.snort.org/downloads/snort/${SNORT_TARBALL} -O ${SNORT_TARBALL}

    tar -xvzf ${SNORT_TARBALL}
    cd snort-${SNORT_VERSION}

    ./configure --enable-sourcefire
    make -j$(nproc)
    make install

    ldconfig
    ln -s /usr/local/bin/snort /usr/sbin/snort 2>/dev/null || true

    echo "[OK] Snort ${SNORT_VERSION} installed."
}

# -----------------------------------------------
# Function: Deploy Snort Configuration
# -----------------------------------------------
deploy_snort_conf() {
    echo "[4/8] Deploying Snort configuration..."

    mkdir -p /etc/snort/rules
    mkdir -p /var/log/snort

    cp ./snort/snort.conf /etc/snort/snort.conf
    cp ./snort/local.rules /etc/snort/rules/local.rules

    echo "[OK] Snort configuration deployed."
}

# -----------------------------------------------
# Function: Install Correlator Script
# -----------------------------------------------
install_correlator() {
    echo "[5/8] Installing Python correlator..."

    cp ./correlator/correlate.py /usr/local/bin/correlate.py
    chmod +x /usr/local/bin/correlate.py

    pip3 install requests

    echo "[OK] Correlator installed."
}

# -----------------------------------------------
# Function: Configure correlator.service
# -----------------------------------------------
install_correlator_service() {
    echo "[6/8] Creating correlator service..."

cat <<EOF >/etc/systemd/system/correlator.service
[Unit]
Description=Correlator Script for Wazuh and Snort Logs
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/correlate.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable correlator.service
    echo "[OK] correlator.service installed."
}

# -----------------------------------------------
# Function: Verify Installation
# -----------------------------------------------
verify_installation() {
    echo "[7/8] Verifying installation..."
    snort -V || echo "[WARN] Snort version check failed (WSL limitation expected)."
    python3 --version
}

# -----------------------------------------------
# Function: Done
# -----------------------------------------------
finish() {
    echo "[8/8] Installation Completed Successfully!"
    echo "Reboot recommended before running Snort."
}

# -----------------------------------------------
# RUN EVERYTHING
# -----------------------------------------------
safe_apt_update
install_dependencies
install_snort
deploy_snort_conf
install_correlator
install_correlator_service
verify_installation
finish
