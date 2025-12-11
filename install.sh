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
# Step 1 – Install system dependencies
# ------------------------------------------------------------
echo
echo "[1/6] Installing system dependencies..."

apt update -y
apt install -y build-essential autoconf automake libtool pkg-config \
               libpcap-dev libpcre3-dev libdumbnet-dev zlib1g-dev \
               libluajit-5.1-dev liblzma-dev libtirpc-dev wget curl git \
               python3 python3-pip flex bison

# ------------------------------------------------------------
# Step 2 – Install DAQ 2.0.7 (REQUIRED FOR SNORT 2.9.x)
# ------------------------------------------------------------
echo
echo "[2/6] Installing DAQ 2.0.7..."

cd /tmp
rm -rf daq-2.0.7*
wget https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq-2.0.7.tar.gz
tar -xvzf daq-2.0.7.tar.gz
cd daq-2.0.7

echo "[INFO] Applying DAQ compatibility patches..."

# Remove RPCAP functions that break on new libpcap
sed -i 's/pcap_remoteact_accept_ex//g' ./config/acinclude.m4 || true
sed -i 's/pcap_remoteact_accept//g'  ./config/acinclude.m4 || true

# Fix tirpc paths
export CPPFLAGS="-I/usr/include/tirpc"
export LDFLAGS="-ltirpc"

echo "[INFO] Building DAQ..."
./configure --enable-static
make -j$(nproc)
make install
ldconfig

echo "[INFO] Verifying DAQ installation..."
if [ ! -f /usr/local/bin/daq-modules-config ]; then
    echo "[ERROR] DAQ installation failed!"
    exit 1
fi

echo "[SUCCESS] DAQ installed."

# ------------------------------------------------------------
# Step 3 – Download Snort 2.9.20
# ------------------------------------------------------------
echo
echo "[3/6] Downloading Snort 2.9.20 source..."

cd /tmp
rm -rf snort-2.9.20*
wget https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort-2.9.20.tar.gz
tar -xvzf snort-2.9.20.tar.gz
cd snort-2.9.20

# ------------------------------------------------------------
# Step 4 – Patch Snort (remove broken plugins + RPCAP)
# ------------------------------------------------------------
echo
echo "[4/6] Applying Snort patches..."

cd src

# Remove tcpdump output plugin (breaks on new systems)
rm -f output-plugins/spo_log_tcpdump.c
rm -f output-plugins/spo_log_tcpdump.h
sed -i 's/LogTcpdumpSetup();//g' plugbase.c
sed -i 's/LogTcpdumpReset();//g' snort.c

# Remove null logging plugin
sed -i 's/LogNullSetup();//g' plugbase.c

# Disable RPCAP features that reference SOCKET type
export CPPFLAGS="-I/usr/include/tirpc -DRPCAP_SUPPORT=0 -DPCAP_SUPPORT=0"
export LDFLAGS="-ltirpc"

cd ..

# ------------------------------------------------------------
# Step 5 – Build + install Snort
# ------------------------------------------------------------
echo
echo "[5/6] Building Snort..."

./configure --enable-sourcefire --enable-open-appid
make -j$(nproc)
make install

echo "[INFO] Snort installation complete."
snort -V || { echo "[ERROR] Snort failed to install."; exit 1; }

# ------------------------------------------------------------
# Step 6 – Snort configuration + correlator
# ------------------------------------------------------------
echo
echo "[6/6] Setting up Snort directories..."

mkdir -p /etc/snort/rules
mkdir -p /etc/snort/preproc_rules
mkdir -p /var/log/snort
mkdir -p /usr/local/lib/snort_dynamicrules

touch /etc/snort/rules/local.rules

groupadd -f snort
id -u snort &>/dev/null || useradd snort -r -s /sbin/nologin

chmod -R 5775 /etc/snort
chmod -R 5775 /var/log/snort

echo "[INFO] Installing correlator..."

mkdir -p /opt/correlator
if [ -d "$HOME/agent-installation/correlator" ]; then
    cp "$HOME/agent-installation/correlator/"*.py /opt/correlator/
fi

pip3 install requests

echo
echo "=============================================="
echo " INSTALLATION COMPLETE – SNORT + DAQ + CORRELATOR"
echo "=============================================="
