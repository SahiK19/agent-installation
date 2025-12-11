#!/bin/bash
set -e

REPO_URL="https://github.com/SahiK19/agent-installation.git"
INSTALL_DIR="/opt/agent-installation"

echo "=============================================="
echo "     AGENT INSTALLATION PACKAGE – FULL SETUP"
echo "=============================================="

# ---------------------------------------------------------
#  OS DETECTION
# ---------------------------------------------------------
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID}"
    OS_CODENAME="${VERSION_CODENAME}"
else
    echo "ERROR: Cannot detect OS version."
    exit 1
fi

echo "[INFO] Detected OS: $OS_ID ($OS_CODENAME)"

# ---------------------------------------------------------
#  FUNCTION: INSTALL SNORT3 VIA OFFICIAL REPOSITORY
# ---------------------------------------------------------
install_snort3() {
    echo
    echo "=============================================="
    echo "[INFO] Installing Snort 3 from official repository"
    echo "=============================================="

    apt update -y
    apt install -y wget gnupg lsb-release

    echo "[INFO] Adding Snort3 GPG Key..."
    wget -O snort3.key https://snort.org/downloads/snort3/snort3-apt-key.asc
    apt-key add snort3.key
    rm -f snort3.key

    echo "[INFO] Adding Snort3 apt repository..."
    echo "deb https://pkgs.snort.org/debian $OS_CODENAME main" \
        | tee /etc/apt/sources.list.d/snort3.list

    echo "[INFO] Updating apt..."
    apt update -y

    echo "[INFO] Installing Snort3..."
    if ! apt install -y snort3; then
        echo "ERROR: Failed to install Snort3. Cannot continue."
        exit 1
    fi

    echo "[OK] Snort3 installed successfully."
}

# ---------------------------------------------------------
#  STEP 1 — UPDATE SYSTEM & INSTALL BASE PACKAGES
# ---------------------------------------------------------
echo
echo "[1/6] Updating system packages..."
apt update -y
apt install -y git python3 python3-pip wget gnupg

# Install Snort 3 using Method A
install_snort3

# ---------------------------------------------------------
#  STEP 2 — DOWNLOAD INSTALLATION PACKAGE
# ---------------------------------------------------------
echo
echo "[2/6] Downloading installation package from GitHub..."

rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "ERROR: Failed to clone repository!"
    exit 1
fi

SNORT_SRC="$INSTALL_DIR/snort_installation"
CORR_SRC="$INSTALL_DIR/correlator"

# ---------------------------------------------------------
#  STEP 3 — INSTALL SNORT CONFIGURATION
# ---------------------------------------------------------
echo
echo "[3/6] Installing Snort configuration..."

mkdir -p /etc/snort/rules

# Copy repo configuration
cp "$SNORT_SRC/snort.lua" /etc/snort/snort.lua 2>/dev/null || true
cp "$SNORT_SRC/snort.conf" /etc/snort/snort.conf 2>/dev/null || true
cp -r "$SNORT_SRC/rules/"* /etc/snort/rules/ 2>/dev/null || true

# Snort3 runs as user "snort" by default; create if missing
if ! id snort >/dev/null 2>&1; then
    echo "[INFO] Creating Snort system user..."
    useradd -r -s /usr/sbin/nologin snort
fi

chown -R snort:snort /etc/snort
chmod -R 644 /etc/snort/rules/* || true

echo "[OK] Snort configuration installed."

# ---------------------------------------------------------
#  STEP 4 — INSTALL CORRELATOR SCRIPT
# ---------------------------------------------------------
echo
echo "[4/6] Installing correlator script..."

if [ ! -f "$CORR_SRC/correlate.py" ]; then
    echo "ERROR: correlate.py missing in repo!"
    exit 1
fi

cp "$CORR_SRC/correlate.py" /usr/local/bin/correlate.py
chmod +x /usr/local/bin/correlate.py

echo "[OK] correlate.py installed."

# ---------------------------------------------------------
#  STEP 5 — INSTALL SYSTEMD SERVICE
# ---------------------------------------------------------
echo
echo "[5/6] Installing correlator systemd service..."

if [ ! -f "$CORR_SRC/correlator.service" ]; then
    echo "ERROR: correlator.service missing in repo!"
    exit 1
fi

cp "$CORR_SRC/correlator.service" /etc/systemd/system/correlator.service

systemctl daemon-reload
systemctl enable correlator.service
systemctl restart correlator.service

echo "[OK] correlator.service enabled and started."

# ---------------------------------------------------------
# STEP 6 — VERIFY INSTALLATION
# ---------------------------------------------------------
echo
echo "[6/6] Verifying service status..."
systemctl status correlator.service --no-pager || true

echo
echo "=============================================="
echo "   ✔ INSTALLATION COMPLETED SUCCESSFULLY"
echo "=============================================="
 
