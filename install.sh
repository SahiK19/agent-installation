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
echo "[1/6] Installing system dependencies..."

apt update -y
apt install -y build-essential autoconf automake libtool pkg-config \
               libpcap-dev libpcre3-dev libdumbnet-dev zlib1g-dev \
               libluajit-5.1-dev liblzma-dev libtirpc-dev wget curl git \
               python3 python3-pip flex bison


# ------------------------------------------------------------
# Step 2 – Install DAQ 2.0.7
# ------------------------------------------------------------
echo "[2/6] Installing DAQ 2.0.7..."

cd /tmp
rm -rf daq-2.0.7*
wget -q https://www.snort.org/downloads/snort/daq-2.0.7.tar.gz -O daq-2.0.7.tar.gz
tar -xzf daq-2.0.7.tar.gz
cd daq-2.0.7

# Patch RPCAP issues
sed -i 's/pcap_remoteact_accept_ex//g' aclocal.m4 configure || true
sed -i 's/pcap_remoteact_accept//g'  aclocal.m4 configure || true

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
echo "[3/6] Downloading Snort 2.9.20..."

cd /tmp
rm -rf snort-2.9.20*
wget -q https://www.snort.org/downloads/snort/snort-2.9.20.tar.gz -O snort-2.9.20.tar.gz
tar -xzf snort-2.9.20.tar.gz
cd snort-2.9.20


# ------------------------------------------------------------
# Step 4 – Patch Snort
# ------------------------------------------------------------
echo "[4/6] Applying Snort patches..."

cd src

# Remove broken plugin
rm -f output-plugins/spo_log_tcpdump.c output-plugins/spo_log_tcpdump.h

# Remove bad function calls
sed -i 's/LogTcpdumpSetup();//g' plugbase.c
sed -i 's/LogTcpdumpReset();//g' snort.c

# Remove NULL logging
sed -i 's/LogNullSetup();//g' plugbase.c

# Remove includes
sed -i '/spo_log_tcpdump.h/d' plugbase.c snort.c

cd ..
autoreconf -fi || true

# Remove Makefile entries
find . -type f -name "Makefile*" -exec sed -i '/spo_log_tcpdump/d' {} \;

cd src
export CPPFLAGS="-I/usr/include/tirpc -DRPCAP_SUPPORT=0 -DPCAP_SUPPORT=0"
export LDFLAGS="-ltirpc"
cd ..


# ------------------------------------------------------------
# Step 5 – Build Snort
# ------------------------------------------------------------
echo "[5/6] Building Snort..."

./configure --enable-sourcefire --disable-open-appid
make -j$(nproc)
make install

snort -V || { echo "[ERROR] Snort installation FAILED!"; exit 1; }


# ------------------------------------------------------------
# Step 6 – Install Snort config + ALL RULES
# ------------------------------------------------------------
echo "[6/6] Setting up Snort configuration..."

rm -f /etc/snort/snort.conf
rm -rf /etc/snort/rules

mkdir -p /etc/snort/rules /etc/snort/preproc_rules /var/log/snort \
         /usr/local/lib/snort_dynamicrules

# Install snort.conf from repo
wget -q https://raw.githubusercontent.com/SahiK19/agent-installation/main/snort_installation/snort.conf \
    -O /etc/snort/snort.conf
echo " - Installed snort.conf"

# ------------------------------------------------------------
# Copy ALL rule files from GitHub
# ------------------------------------------------------------
echo "[INFO] Downloading ALL rule files from GitHub..."

RULES_BASE_URL="https://raw.githubusercontent.com/SahiK19/agent-installation/main/snort_installation/rules"

# List all .rules files in your GitHub folder
RULE_FILES=$(curl -s https://api.github.com/repos/SahiK19/agent-installation/contents/snort_installation/rules \
    | grep "\"name\"" | grep ".rules" | cut -d '"' -f 4)

for rule in $RULE_FILES; do
    echo " - Installing rule: $rule"
    wget -q "$RULES_BASE_URL/$rule" -O "/etc/snort/rules/$rule"
done


groupadd -f snort
id -u snort &>/dev/null || useradd -r -s /sbin/nologin -g snort snort

chmod -R 5775 /etc/snort /var/log/snort


# ------------------------------------------------------------
# Install correlator + systemd
# ------------------------------------------------------------
echo "[INFO] Installing correlator..."

mkdir -p /opt/correlator
CORR_URL="https://raw.githubusercontent.com/SahiK19/agent-installation/main/correlator"

wget -q "$CORR_URL/correlate.py" -O /opt/correlator/correlate.py
chmod +x /opt/correlator/correlate.py

wget -q "$CORR_URL/correlator.service" -O /etc/systemd/system/correlator.service

pip3 install --break-system-packages requests

systemctl daemon-reload
systemctl enable correlator.service
systemctl restart correlator.service

echo "[INFO] Correlator service status:"
systemctl status correlator.service --no-pager || true


echo "=============================================="
echo " INSTALLATION COMPLETE – SNORT + DAQ + FULL RULESET + CORRELATOR"
echo "=============================================="
