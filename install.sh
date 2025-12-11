#!/bin/bash

set -e

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

# ------------------------------------------------------------
# Detect OS
# ------------------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_CODENAME
else
    OS_NAME="unknown"
    OS_VERSION="unknown"
fi

echo "[INFO] Detected OS: $OS_NAME ($OS_VERSION)"

# ------------------------------------------------------------
# Step 1 – System update + dependencies
# ------------------------------------------------------------
echo
echo "[1/6] Updating system packages..."
apt update -y
apt install -y build-essential libpcap-dev libpcre3-dev libdumbnet-dev \
               zlib1g-dev libluajit-5.1-dev liblzma-dev libtirpc-dev \
               pkg-config wget curl git python3 python3-pip

# ------------------------------------------------------------
# Step 2 – Download Snort 2.9.20 source
# ------------------------------------------------------------
echo
echo "[2/6] Downloading Snort 2.9.20..."
rm -rf /tmp/snort-2.9.20*
cd /tmp
wget https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort-2.9.20.tar.gz
tar -xvzf snort-2.9.20.tar.gz
cd snort-2.9.20

# ------------------------------------------------------------
# Step 3 – Apply Debian-Trixie compatibility patches
# ------------------------------------------------------------
echo
echo "[3/6] Applying Snort compatibility patches..."

cd /tmp/snort-2.9.20/src

echo "[INFO] Removing tcpdump plugin..."
rm -f output-plugins/spo_log_tcpdump.c
rm -f output-plugins/spo_log_tcpdump.h
grep -Rl "spo_log_tcpdump" ../ | xargs sed -i '/spo_log_tcpdump/d'
sed -i 's/LogTcpdumpSetup();//g' plugbase.c
sed -i 's/LogTcpdumpReset();//g' snort.c
sed -i '/log_tcpdump/d' parser.c

echo "[INFO] Removing null logging plugin..."
sed -i 's/LogNullSetup();//g' plugbase.c
grep -Rl "sp_null" ../ | xargs sed -i '/sp_null/d' || true

echo "[INFO] Disabling RPCAP + SOCKET support..."
export CPPFLAGS="-I/usr/include/tirpc -DRPCAP_SUPPORT=0 -DPCAP_SUPPORT=0"
export LDFLAGS="-ltirpc"

sed -i 's/pcap_remoteact_accept_ex//g' ../configure || true
sed -i 's/pcap_remoteact_accept//g' ../configure || true

echo "[INFO] Patch applied successfully."

cd /tmp/snort-2.9.20

# ------------------------------------------------------------
# Step 4 – Configure + build Snort
# ------------------------------------------------------------
echo
echo "[4/6] Building Snort..."
./configure --enable-sourcefire --enable-open-appid
make -j$(nproc)
make install

echo
echo "=== Verifying Snort version ==="
snort -V || { echo "Snort build failed"; exit 1; }

# ------------------------------------------------------------
# Step 5 – Prepare Snort directories
# ------------------------------------------------------------
echo
echo "[5/6] Preparing /etc/snort..."

mkdir -p /etc/snort/rules
mkdir -p /etc/snort/preproc_rules
mkdir -p /var/log/snort
mkdir -p /usr/local/lib/snort_dynamicrules

touch /etc/snort/rules/local.rules

groupadd -f snort
id -u snort &>/dev/null || useradd snort -r -s /sbin/nologin

chmod -R 5775 /etc/snort
chmod -R 5775 /var/log/snort

# ------------------------------------------------------------
# Step 6 – Install Python correlator
# ------------------------------------------------------------
echo
echo "[6/6] Installing Python correlator..."

# Create directory for correlator
mkdir -p /opt/correlator

# Copy correlator script from repo
if [ -d "$HOME/agent-installation/correlator" ]; then
    cp "$HOME/agent-installation/correlator/"*.py /opt/correlator/
fi

pip3 install requests

echo
echo "=============================================="
echo "  INSTALLATION COMPLETE – SNORT + CORRELATOR"
echo "=============================================="
