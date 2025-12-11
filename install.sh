#!/bin/bash
set -e

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_CODENAME
else
    OS_NAME="unknown"
    OS_VERSION="unknown"
fi

echo "[INFO] Detected OS: $OS_NAME ($OS_VERSION)"

echo
echo "[1/7] Updating system packages..."
apt update -y
apt install -y build-essential libpcap-dev libpcre3-dev libdumbnet-dev \
               zlib1g-dev libluajit-5.1-dev liblzma-dev libtirpc-dev \
               pkg-config wget curl git python3 python3-pip automake autoconf libtool

# =====================================================================
# STEP 2 — INSTALL DAQ (Data Acquisition Library) REQUIRED BY SNORT 2
# =====================================================================
echo
echo "[2/7] Installing DAQ 2.0.7..."

cd /tmp
rm -rf daq-2.0.7*
wget https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq-2.0.7.tar.gz
tar -xvzf daq-2.0.7.tar.gz
cd daq-2.0.7

# Patch DAQ for Debian 12/13 glibc and tirpc
echo "[INFO] Applying DAQ compatibility patches..."

export CPPFLAGS="-I/usr/include/tirpc"
export LDFLAGS="-ltirpc"

# Replace deprecated rpc headers
grep -Rl "<rpc/" . | xargs sed -i 's|<rpc/|<tirpc/|g' || true

./configure --enable-static
make -j"$(nproc)"
make install

ldconfig

echo "[INFO] DAQ installed successfully."

# =====================================================================
# STEP 3 — DOWNLOAD SNORT 2.9.20
# =====================================================================
echo
echo "[3/7] Downloading Snort 2.9.20..."

cd /tmp
rm -rf snort-2.9.20*
wget https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort-2.9.20.tar.gz
tar -xvzf snort-2.9.20.tar.gz
cd snort-2.9.20/src

echo "[INFO] Removing tcpdump plugin..."
rm -f output-plugins/spo_log_tcpdump.c
rm -f output-plugins/spo_log_tcpdump.h
sed -i 's/LogTcpdumpSetup();//g' ../src/plugbase.c
sed -i 's/LogTcpdumpReset();//g' ../src/snort.c
sed -i '/log_tcpdump/d' ../src/parser.c

echo "[INFO] Adding LogNullSetup stub..."
sed -i '1i #ifndef LogNullSetup\n#define LogNullSetup() /* disabled */\n#endif' plugbase.c

# Disable RPCAP / SOCKET unsupported functions
sed -i 's/pcap_remoteact_accept_ex//g' ../configure || true
sed -i 's/pcap_remoteact_accept//g' ../configure || true

cd /tmp/snort-2.9.20

# =====================================================================
# STEP 4 — BUILD SNORT
# =====================================================================
echo
echo "[4/7] Building Snort..."

export CPPFLAGS="-I/usr/include/tirpc -I/usr/local/include"
export LDFLAGS="-ltirpc -L/usr/local/lib"

./configure --enable-sourcefire --enable-open-appid

make -j"$(nproc)"
make install

echo
echo "=== VERIFYING SNORT INSTALLATION ==="
snort -V || { echo "Snort build failed"; exit 1; }

# =====================================================================
# STEP 5 — SNORT DIRECTORIES
# =====================================================================
echo
echo "[5/7] Preparing /etc/snort..."

mkdir -p /etc/snort/rules /etc/snort/preproc_rules /var/log/snort /usr/local/lib/snort_dynamicrules

touch /etc/snort/rules/local.rules

groupadd -f snort
id -u snort &>/dev/null || useradd snort -r -s /sbin/nologin

chmod -R 5775 /etc/snort /var/log/snort

# =====================================================================
# STEP 6 — INSTALL CORRELATOR
# =====================================================================
echo
echo "[6/7] Installing Python correlator..."

mkdir -p /opt/correlator
if [ -d "$HOME/agent-installation/correlator" ]; then
    cp "$HOME/agent-installation/correlator/"*.py /opt/correlator/
fi

pip3 install requests

# =====================================================================
# DONE
# =====================================================================
echo
echo "=============================================="
echo "   INSTALLATION COMPLETE — SNORT + DAQ + CORRELATOR"
echo "=============================================="
