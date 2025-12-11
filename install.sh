#!/bin/bash
set -e

# ===========================================
#  AGENT INSTALLATION PACKAGE – FULL SETUP
#  Snort 2.9.20 + DAQ 2.0.7 (manual install)
# ===========================================

BASE_DIR="/home/agent_installation_package"
SNORT_DIR="$BASE_DIR/snort_installation"
CORR_DIR="$BASE_DIR/correlator"

DAQ_VERSION="2.0.7"
SNORT_VERSION="2.9.20"

DAQ_TARBALL="daq-${DAQ_VERSION}.tar.gz"
SNORT_TARBALL="snort-${SNORT_VERSION}.tar.gz"

DAQ_URL="https://www.snort.org/downloads/snort/${DAQ_TARBALL}"
SNORT_URL="https://www.snort.org/downloads/snort/${SNORT_TARBALL}"

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

echo
echo "[1/6] Installing build dependencies..."
sudo apt update
sudo apt install -y \
    build-essential \
    autotools-dev \
    libpcap-dev \
    libpcre3-dev \
    libdumbnet-dev \
    zlib1g-dev \
    libluajit-5.1-dev \
    libssl-dev \
    wget \
    python3 python3-pip

echo
echo "[2/6] Downloading DAQ ${DAQ_VERSION}..."
wget -O /tmp/${DAQ_TARBALL} ${DAQ_URL}

echo "[INFO] Extracting DAQ..."
cd /tmp
tar -xvzf ${DAQ_TARBALL}

echo "[INFO] Compiling DAQ..."
cd daq-${DAQ_VERSION}
./configure
make -j$(nproc)
sudo make install

sudo ldconfig
echo "[INFO] DAQ installation complete."

echo
echo "[3/6] Downloading Snort ${SNORT_VERSION}..."
wget -O /tmp/${SNORT_TARBALL} ${SNORT_URL}

echo "[INFO] Extracting Snort..."
cd /tmp
tar -xvzf ${SNORT_TARBALL}

echo "[INFO] Compiling Snort..."
cd snort-${SNORT_VERSION}
./configure --enable-sourcefire
make -j$(nproc)
sudo make install

sudo ldconfig
echo "[INFO] Snort installation complete."

echo
echo "=== Verifying Snort version ==="
snort -V || { echo "Snort not installed correctly"; exit 1; }

echo
echo "[4/6] Preparing /etc/snort directory..."

sudo groupadd snort || true
sudo useradd snort -r -s /sbin/nologin -c SNORT_IDS -g snort || true

sudo mkdir -p /etc/snort
sudo mkdir -p /etc/snort/rules
sudo mkdir -p /etc/snort/preproc_rules
sudo mkdir -p /usr/local/lib/snort_dynamicrules
sudo mkdir -p /var/log/snort

echo
echo "[5/6] Copying custom Snort configuration files..."

if [ ! -f "$SNORT_DIR/snort.conf" ]; then
    echo "ERROR: $SNORT_DIR/snort.conf not found"
    exit 1
fi

sudo cp "$SNORT_DIR/snort.conf" /etc/snort/snort.conf

if [ -d "$SNORT_DIR/rules" ]; then
    sudo cp -r "$SNORT_DIR/rules/"* /etc/snort/rules/ || true
fi

sudo chown -R snort:snort /etc/snort
sudo chmod -R 5775 /etc/snort

echo
echo "[6/6] Installing Python correlator systemd service..."

if [ ! -f "$CORR_DIR/correlate.py" ]; then
    echo "ERROR: $CORR_DIR/correlate.py not found"
    exit 1
fi

if [ ! -f "$CORR_DIR/correlator.service" ]; then
    echo "ERROR: $CORR_DIR/correlator.service not found"
    exit 1
fi

sudo cp "$CORR_DIR/correlate.py" /usr/local/bin/correlate.py
sudo chmod +x /usr/local/bin/correlate.py

sudo cp "$CORR_DIR/correlator.service" /etc/systemd/system/correlator.service

sudo systemctl daemon-reload
sudo systemctl enable correlator.service
sudo systemctl restart correlator.service

echo
echo "=== Verifying correlator.service status ==="
sudo systemctl status correlator.service --no-pager || true

echo
echo "=============================================="
echo "   ✅ Installation completed successfully."
echo "=============================================="
