#!/bin/bash
set -e

echo "================================================="
echo "     AGENT INSTALLATION PACKAGE - FULL INSTALL"
echo "================================================="

# ---------------------------------------------------
# 1. SAFE APT UPDATE (Ubuntu 24.04 / WSL fix)
# ---------------------------------------------------
safe_apt_update() {
    echo "[1/9] Updating system packages (safe mode)..."

    set +e
    apt update -y
    STATUS=$?
    set -e

    if [[ $STATUS -ne 0 ]]; then
        echo "[WARN] APT update returned warnings."
        echo "[INFO] Continuing installation..."
    fi
}

# ---------------------------------------------------
# 2. INSTALL DEPENDENCIES
# ---------------------------------------------------
install_dependencies() {
    echo "[2/9] Installing build dependencies..."

    apt install -y \
        build-essential \
        wget curl git \
        autoconf automake libtool pkg-config \
        python3 python3-pip python3-venv \
        libpcap-dev zlib1g-dev \
        libdumbnet-dev bison flex \
        ethtool net-tools

    echo "[OK] Base dependencies installed."

    # PCRE check (Debian 13 breaks libpcre3-dev)
    if ! dpkg -l | grep -q libpcre3; then
        echo "[INFO] Installing PCRE 8.45 manually (required for Snort)..."

        cd /tmp
        wget https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz -O pcre.tar.gz
        tar -xzf pcre.tar.gz
        cd pcre-8.45

        ./configure
        make -j$(nproc)
        make install
        ldconfig

        echo "[OK] PCRE installed manually."
    fi
}

# ---------------------------------------------------
# 3. INSTALL DAQ 2.0.7
# ---------------------------------------------------
install_daq() {
    echo "[3/9] Installing DAQ 2.0.7 (patched for modern Linux)..."

    cd /tmp
    wget https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq.tar.gz
    tar -xzf daq.tar.gz
    cd daq-2.0.7

    echo "[INFO] Applying DAQ build patch..."

    # Fix: ensure tokdefs.h is generated *before* scanner is compiled
    sed -i 's/sf_scanner.lo: sf_scanner.c tokdefs.h/sf_scanner.lo: tokdefs.h sf_scanner.c/' sfbpf/Makefile.am
    sed -i 's/sf_scanner.lo: sf_scanner.c tokdefs.h/sf_scanner.lo: tokdefs.h sf_scanner.c/' sfbpf/Makefile.in

    # Rebuild auto tools
    autoreconf -fvi

    echo "[INFO] Building DAQ without parallel jobs (required)..."
    ./configure --prefix=/usr/local --enable-static

    # MUST disable parallel jobs or tokdefs.h breaks again
    make -j1
    make install

    ldconfig

    # Fix missing symlinks
    ln -sf /usr/local/bin/daq-modules-config /usr/bin/daq-modules-config
    ln -sf /usr/local/bin/daq-modules-config /usr/sbin/daq-modules-config
    ln -sf /usr/local/lib/libdaq_static.a /usr/lib/libdaq_static.a 2>/dev/null || true
    ln -sf /usr/local/lib/libdaq.a /usr/lib/libdaq.a 2>/dev/null || true

    echo "[OK] DAQ installed with modern compatibility patches."
}


# ---------------------------------------------------
# 4. VERIFY DAQ INSTALLATION
# ---------------------------------------------------
verify_daq() {
    echo "[4/9] Verifying DAQ installation..."

    if [[ ! -f /usr/local/bin/daq-modules-config ]]; then
        echo "[ERROR] daq-modules-config missing. DAQ install failed."
        exit 1
    fi

    if [[ ! -d /usr/local/lib/daq ]]; then
        echo "[ERROR] /usr/local/lib/daq modules missing. DAQ install failed."
        exit 1
    fi

    echo "[OK] DAQ installation verified."
}

# ---------------------------------------------------
# 5. INSTALL SNORT 2.9.20
# ---------------------------------------------------
install_snort() {
    echo "[5/9] Installing Snort 2.9.20..."

    cd /tmp
    wget https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort.tar.gz
    tar -xzf snort.tar.gz
    cd snort-2.9.20

    ./configure --enable-sourcefire
    make -j$(nproc)
    make install

    ldconfig

    ln -sf /usr/local/bin/snort /usr/sbin/snort 2>/dev/null || true

    echo "[OK] Snort installed."
}

# ---------------------------------------------------
# 6. DEPLOY SNORT CONFIGURATION
# ---------------------------------------------------
deploy_snort_conf() {
    echo "[6/9] Deploying Snort configuration..."

    mkdir -p /etc/snort/rules
    mkdir -p /var/log/snort

    cp ./snort/snort.conf /etc/snort/snort.conf
    cp ./snort/local.rules /etc/snort/rules/local.rules

    echo "[OK] Snort configuration deployed."
}

# ---------------------------------------------------
# 7. INSTALL CORRELATOR SCRIPT
# ---------------------------------------------------
install_correlator() {
    echo "[7/9] Installing correlator script..."

    cp ./correlator/correlate.py /usr/local/bin/correlate.py
    chmod +x /usr/local/bin/correlate.py
    pip3 install requests

    echo "[OK] Correlator installed."
}

# ---------------------------------------------------
# 8. INSTALL SYSTEMD SERVICE
# ---------------------------------------------------
install_correlator_service() {
    echo "[8/9] Installing correlator.service..."

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

# ---------------------------------------------------
# 9. FINAL CHECKS
# ---------------------------------------------------
finish() {
    echo "[9/9] Final checks..."
    snort -V || echo "[WARN] Snort version check failed (WSL restriction)."
    python3 --version
    echo "================================================="
    echo "INSTALLATION COMPLETE"
    echo "================================================="
}

# ---------------------------------------------------
# RUN EVERYTHING
# ---------------------------------------------------
safe_apt_update
install_dependencies
install_daq
verify_daq
install_snort
deploy_snort_conf
install_correlator
install_correlator_service
finish
