#!/bin/bash
set -e

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------
. /etc/os-release
echo "[INFO] Detected OS: $ID ($VERSION_CODENAME)"

# ------------------------------------------------------------
# Step 1 – System update + dependencies
# ------------------------------------------------------------
echo
echo "[1/7] Updating system packages..."
apt update -y
apt install -y build-essential libpcap-dev libpcre3-dev libdumbnet-dev \
               zlib1g-dev libluajit-5.1-dev liblzma-dev libtirpc-dev \
               pkg-config wget curl git python3 python3-pip autoconf automake libtool

# ------------------------------------------------------------
# Step 2 – Download & patch DAQ 2.0.7
# ------------------------------------------------------------
echo
echo "[2/7] Downloading and patching DAQ 2.0.7..."

rm -rf /tmp/daq-2.0.7*
cd /tmp
wget https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq.tar.gz
tar -xvzf daq.tar.gz
cd daq-2.0.7

echo "[INFO] Applying TIRPC + RPC patches..."
export CPPFLAGS="-I/usr/include/tirpc"
export LDFLAGS="-ltirpc"

# Fix deprecated RPC paths
grep -Rl "<rpc/" . | xargs sed -i 's|<rpc/|<tirpc/|g' || true

# ------------------------------------------------------------
# Build DAQ
# ------------------------------------------------------------
echo "[INFO] Configuring DAQ..."
./configure --enable-static

echo "[INFO] Building DAQ..."
make -j$(nproc)

echo "[INFO] Installing DAQ..."
make install
ldconfig

# ------------------------------------------------------------
# Verify DAQ installation
# ------------------------------------------------------------
echo "[INFO] Verifying DAQ installation..."
if ldconfig -p | grep -q libdaq; then
    echo "[OK] DAQ successfully installed!"
else
    echo "[ERROR] DAQ installation failed. Snort cannot be built."
    exit 1
fi

# ------------------------------------------------------------
# Step 3 – Download Snort 2.9.20
# ------------------------------------------------------------
echo
echo "[3/7] Downloading Snort 2.9.20..."

rm -rf /tmp/snort-2.9.20*
cd /tmp
wget https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort.tar.gz
tar -xvzf snort.tar.gz
cd snort-2.9.20

# ------------------------------------------------------------
# Step 4 – Remove incompatible plugins
# ------------------------------------------------------------
echo
echo "[4/7] Applying Snort compatibility patches..."

cd src

echo "[INFO] Removing tcpdump plugin..."
rm -f output-plugins/spo_log_tcpdump.c
rm -f output-plugins/spo_log_tcpdump.h
sed -i '/spo_log_tcpdump/d' plugbase.c parser.c snort.c

echo "[INFO] Removing LogNull plugin..."
sed -i 's/LogNullSetup();//g' plugbase.c

echo "[INFO] Disabling RPCAP & SOCKET..."
export CPPFLAGS="-I/usr/include/tirpc -DRPCAP_SUPPORT=0 -DPCAP_SUPPORT=0"
export LDFLAGS="-ltirpc"

cd ..

# ------------------------------------------------------------
# Step 5 – Build Snort
# ------------------------------------------------------------
echo
echo "[5/7] Building Snort..."

./configure --enable-sourcefire --enable-open-appid
make -j$(nproc)
make install

echo
echo "=== Snort Version Check ==="
snort -V

# ------------------------------------------------------------
# Step 6 – Snort directories
# ------------------------------------------------------------
echo
echo "[6/7] Preparing Snort directories..."

mkdir -p /etc/snort/rules \
         /etc/snort/preproc_rules \
         /var/log/snort \
         /usr/local/lib/snort_dynamicrules

touch /etc/snort/rules/local.rules

groupadd -f snort
id -u snort &>/dev/null || useradd snort -r -s /sbin/nologin

chmod -R 5775 /etc/snort /var/log/snort

# ------------------------------------------------------------
# Step 7 – Install Python correlator
# ------------------------------------------------------------
echo
echo "[7/7] Installing Python correlator..."

mkdir -p /opt/correlator

if [ -d "$HOME/agent-installation/correlator" ]; then
    cp "$HOME/agent-installation/correlator/"*.py /opt/correlator/
fi

pip3 install requests

echo
echo "=============================================="
echo "   INSTALLATION COMPLETE – SNORT + DAQ + CORRELATOR"
echo "=============================================="
