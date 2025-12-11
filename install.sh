#!/bin/bash
set -e

# ===========================================
#  AGENT INSTALLATION PACKAGE – FULL SETUP
#  Snort 2.9.20 + DAQ 2.0.7 (manual build)
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
echo "[0/6] Downloading GitHub package files..."
sudo rm -rf $BASE_DIR
sudo mkdir -p $BASE_DIR
cd $BASE_DIR

wget https://github.com/SahiK19/agent-installation/archive/refs/heads/main.zip -O package.zip
sudo apt install unzip -y
unzip package.zip
mv agent-installation-main/* .
rm -rf agent-installation-main package.zip
echo "[OK] Package files downloaded."
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
    libtirpc-dev \
    wget \
    python3 python3-pip unzip

echo
echo "[2/6] Installing DAQ ${DAQ_VERSION}..."
wget -O /tmp/${DAQ_TARBALL} ${DAQ_URL}
cd /tmp
tar -xvzf ${DAQ_TARBALL}
cd daq-${DAQ_VERSION}

./configure
make -j$(nproc)
sudo make install
sudo ldconfig
echo "[INFO] DAQ installation complete."
echo

echo "[3/6] Installing Snort ${SNORT_VERSION}..."
wget -O /tmp/${SNORT_TARBALL} ${SNORT_URL}
cd /tmp
tar -xvzf ${SNORT_TARBALL}
cd snort-${SNORT_VERSION}

echo "[INFO] Applying tcpdump plugin removal patch (full patch)..."

# Remove broken plugin source files
rm -f src/output-plugins/spo_log_tcpdump.c
rm -f src/output-plugins/spo_log_tcpdump.h

# Remove references from autotools templates
sed -i '/spo_log_tcpdump/d' src/output-plugins/Makefile.am
sed -i '/spo_log_tcpdump/d' src/output-plugins/Makefile.in
sed -i '/spo_log_tcpdump.o/d' src/output-plugins/Makefile.am
sed -i '/spo_log_tcpdump.o/d' src/output-plugins/Makefile.in

# tirpc fix for missing rpc/rpc.h
export CPPFLAGS="-I/usr/include/tirpc"
export LDFLAGS="-ltirpc"

./configure --enable-sourcefire

# Remove references from generated Makefile
sed -i '/spo_log_tcpdump/d' src/output-plugins/Makefile
sed -i '/spo_log_tcpdump.o/d' src/output-plugins/Makefile
sed -i '/log_tcpdump/d' src/output-plugins/Makefile

echo "[INFO] Building Snort..."
make -j$(nproc)
sudo make install
sudo ldconfig

echo "[INFO] Snort installation complete."
echo

echo "=== Verifying Snort version ==="
snort -V || { echo "Snort failed to install"; exit 1; }
echo

echo "[4/6] Preparing /etc/snort directory..."

sudo groupadd snort || true
sudo useradd snort -r -s /sbin/nologin -c SNORT_IDS -g snort || true

sudo mkdir -p /etc/snort/rules
sudo mkdir -p /etc/snort/preproc_rules
sudo mkdir -p /usr/local/lib/snort_dynamicrules
sudo mkdir -p /var/log/snort

echo
ec
