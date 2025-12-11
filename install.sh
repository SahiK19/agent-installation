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
# Step 1 – Install dependencies
# ------------------------------------------------------------
echo
echo "[1/6] Installing system dependencies..."

apt update -y
apt install -y build-essential autoconf automake libtool pkg-config \
               libpcap-dev libpcre3-dev libdumbnet-dev zlib1g-dev \
               libluajit-5.1-dev liblzma-dev libtirpc-dev wget curl git \
               python3 python3-pip flex bison

# ------------------------------------------------------------
# Step 2 – Install DAQ 2.0.7
# ------------------------------------------------------------
echo
echo "[2/6] Installing DAQ 2.0.7..."

cd /tmp
rm -rf daq-2.0.7*
wget -q https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq-2.0.7.tar.gz
tar -xzf daq-2.0.7.tar.gz
cd daq-2.0.7

# Patch RPCAP issues
sed -i 's/pcap_remoteact_accept_ex//g' ./aclocal.m4 || true
sed -i 's/pcap_remoteact_accept//g'  ./aclocal.m4 || true
sed -i 's/pcap_remoteact_accept_ex//g' ./configure || true
sed -i 's/pcap_remoteact_accept//g'  ./configure || true

export CPPFLAGS="-I/usr/include/tirpc"
export LDFLAGS="-ltirpc"

# Fix build order
cd sfbpf
bison -d grammar.y -o grammar.c
cp grammar.h tokdefs.h
cd ..

autoreconf -fi || true

echo "[INFO] Building DAQ..."
./configure --enable-static
make -j$(nproc)
make install
ldconfig

if [ ! -f /usr/local/bin/daq-modules-config ]; then
    echo "[ERROR] DAQ installation FAILED!"
    exit 1
fi

echo "[SUCCESS] DAQ installed."

# ------------------------------------------------------------
# Step 3 – Install Snort 2.9.20
# ------------------------------------------------------------
echo
echo "[3/6] Downloading Snort 2.9.20..."

cd /tmp
rm -rf snort-2.9.20*
wget -q https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort-2.9.20.tar.gz
tar -xzf snort-2.9.20.tar.gz
cd snort-2.9.20

# ------------------------------------------------------------
# Step 4 – Patch Snort
# ------------------------------------------------------------
echo
echo "[4/6] Applying Snort patches..."

cd src

echo "[INFO] Removing broken tcpdump plugin..."
rm -f output-plugins/spo_log_tcpdump.c
rm -f output-plugins/spo_log_tcpdump.h

echo "[INFO] Removing tcpdump-related function calls..."
sed -i 's/LogTcpdumpSetup();//g' plugbase.c
sed -i 's/LogTcpdumpReset();//g' snort.c

echo "[INFO] Removing NULL logging plugin..."
sed -i 's/LogNullSetup();//g' plugbase.c

echo "[INFO] Removing leftover include statements..."
sed -i '/spo_log_tcpdump.h/d' plugbase.c
sed -i '/spo_log_tcpdump.h/d' snort.c

cd ..

autoreconf -fi || true

echo "[INFO] Removing tcpdump entries in all Makefiles..."
find . -type f -name "Makefile*" -exec sed -i '/spo_log_tcpdump/d' {} \;

cd src
export CPPFLAGS="-I/usr/include/tirpc -DRPCAP_SUPPORT=0 -DPCAP_SUPPORT=0"
export LDFLAGS="-ltirpc"
cd ..

# ------------------------------------------------------------
# Step 5 – Build Snort
# ------------------------------------------------------------
echo
echo "[5/6] Building Snort..."

./configure --enable-sourcefire --disable-open-appid
make -j$(nproc)
make install

snort -V || { echo "[ERROR] Snort install FAILED!"; exit 1; }

# ------------------------------------------------------------
# Step 6 – Setup Snort folders + Install correlator
# ------------------------------------------------------------
echo
echo "[6/6] Setting up Snort folders & correlator..."

mkdir -p /etc/snort/rules
mkdir -p /etc/snort/preproc_rules
mkdir -p /var/log/snort
mkdir -p /usr/local/lib/snort_dynamicrules

touch /etc/snort/rules/local.rules

groupadd -f snort
id -u snort &>/dev/null || useradd -r -s /sbin/nologin -g snort snort

chmod -R 5775 /etc/snort
chmod -R 5775 /var/log/snort

# ------------------------------------------------------------
# Install correlator
# ------------------------------------------------------------
echo "[INFO] Installing correlator from GitHub..."

mkdir -p /opt/correlator
CORR_URL="https://raw.githubusercontent.com/SahiK19/agent-installation/main/correlator"

echo "[INFO] Downloading correlate.py..."
if wget -q "$CORR_URL/correlate.py" -O "/opt/correlator/correlate.py"; then
    echo " - correlate.py installed"
else
    echo "ERROR: Failed to download correlate.py"
    exit 1
fi

chmod +x /opt/correlator/correlate.py

echo "[INFO] Installing Python dependencies..."
pip3 install --break-system-packages requests

echo
echo "=============================================="
echo " INSTALLATION COMPLETE – SNORT + DAQ + CORRELATOR"
echo "=============================================="
