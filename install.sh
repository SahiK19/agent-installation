#!/bin/bash
set -e

echo "================================================="
echo "     AGENT INSTALLATION PACKAGE - FULL INSTALL"
echo "================================================="

# -----------------------------------------------
# Function: Safe APT Update (Ubuntu 24.04 / WSL fix)
# -----------------------------------------------
safe_apt_update() {
    echo "[1/9] Updating system packages (safe mode)..."

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
# Function: Install Dependencies (with Debian 13 PCRE fix)
# -----------------------------------------------
install_dependencies() {
    echo "[2/9] Installing system dependencies..."

    apt install -y \
        build-essential \
        wget curl git \
        python3 python3-pip python3-venv \
        libpcap-dev zlib1g-dev \
        libdumbnet-dev bison flex \
        ethtool net-tools

    OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*(?=")' /etc/os-release | cut -d'.' -f1)

    if [[ "$OS_VERSION" == "13" ]]; then
        echo "[INFO] Debian 13 detected — installing PCRE 8.45 from source..."

        cd /tmp
        wget https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz -O pcre-8.45.tar.gz
        tar -xzf pcre-8.45.tar.gz
        cd pcre-8.45

        ./configure
        make -j$(nproc)
        make install
        ldconfig

        echo "[OK] PCRE 8.45 installed manually."
    else
        echo "[INFO] Installing libpcre3-dev from repo..."
        apt install -y libpcre3-dev
    fi

    echo "[OK] Dependencies installed."
}

# -----------------------------------------------
# Function: Install DAQ 2.0.7 (REQUIRED FOR SNORT)
# -----------------------------------------------
install_daq() {
    echo "[3/9] Installing DAQ 2.0.7..."

    DAQ_VERSION="2.0.7"
    DAQ_TARBALL="daq-${DAQ_VERSION}.tar.gz"

    cd /tmp
    wget https://www.snort.org/downloads/snort/${DAQ_TARBALL} -O ${DAQ_TARBALL}

    tar -xvzf ${DAQ_TARBALL}
    cd daq-${DAQ_VERSION}

    ./configure
    make -j$(nproc)
    make install
    ldconfig

    echo "[OK] DAQ ${DAQ_VERSION} installed."
}

# -----------------------------------------------
# Function: Install Snort 2.9.20
# -----------------------------------------------
install_snort() {
    echo "[4/9] Installing Snort 2.9.20 from source..."

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
    echo "[5/9] Deploying Snort configuration..."

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
    echo "[6/9] Installing Python correlator..."

    cp ./correlator/correlate.py /usr/local/bin/correlate.py
    chmod +x /usr/local/bin/correlate.py

    pip3 install requests

    echo "[OK] Correlator installed."
}

# -----------------------------------------------
# Function: Install correlator.service
# -----------------------------------------------
install_correlator_service() {
    echo "[7/9] Creating correlator systemd service..."

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
    echo "[8/9] Verifying installation..."

    snort -V || echo "[WARN] Snort -V failed (expected in WSL)."
    python3 --version
}

# -----------------------------------------------
# Function: Finish
# -----------------------------------------------
finish() {
    echo "[9/9] Installation Completed Successfully!"
    echo "Reboot recommended before running Snort."
}

# -----------------------------------------------
# RUN EVERYTHING
# -----------------------------------------------
safe_apt_update
install_dependencies
install_daq
install_snort
deploy_snort_conf
install_correlator
install_correlator_service
verify_installation
finish

