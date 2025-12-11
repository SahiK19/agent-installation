#!/usr/bin/env python3

import time
import json
import re
from datetime import datetime, timedelta, timezone

import requests

# ---------- CONFIG ----------

SNORT_FAST_LOG = "/var/log/snort/snort.alert.fast"
WAZUH_ALERTS_URL = "http://47.130.204.203:8000/alerts.json"

# Time windows for correlation
SCAN_TO_SUDO_WINDOW = timedelta(seconds=60)
SCAN_TO_SSH_WINDOW = timedelta(seconds=120)
SSH_FAIL_WINDOW = timedelta(seconds=120)
REVERSE_SHELL_WINDOW = timedelta(seconds=180)
PACKAGE_INSTALL_WINDOW = timedelta(seconds=90)

# How often to poll Wazuh alerts.json (seconds)
WAZUH_POLL_INTERVAL = 5


# ---------- HELPERS ----------

def parse_wazuh_timestamp(ts: str) -> datetime:
    """
    Wazuh timestamp example:
    2025-12-04T20:18:01.093+0000
    """
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%f%z")
    except Exception:
        # Fallback: treat as naive UTC
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)


def extract_first_ip(text: str) -> str | None:
    """Return first IPv4 addr in text, or None."""
    m = re.search(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text)
    return m.group(0) if m else None


# ---------- SNORT CLASSIFIERS ----------

def is_nmap_scan_snort(line: str) -> bool:
    """Detect Nmap scans (ICMP, ping sweep)"""
    up = line.upper()
    return "NMAP" in up or "PING SWEEP" in up


def is_port_scan_snort(line: str) -> bool:
    """Detect SYN/FIN/Xmas scans"""
    up = line.upper()
    return ("SYN SCAN" in up or "FIN SCAN" in up or
            "XMAS SCAN" in up or "SCAN DETECTED" in up)


def is_ssh_bruteforce_snort(line: str) -> bool:
    """Detect SSH brute force from Snort"""
    up = line.upper()
    return "SSH BRUTE FORCE" in up


def is_reverse_shell_snort(line: str) -> bool:
    """Detect reverse shell attempts"""
    up = line.upper()
    return "REVERSE SHELL" in up


# ---------- WAZUH CLASSIFIERS ----------

def is_sudo_or_priv_esc_wazuh(alert: dict) -> bool:
    """Detect privilege escalation (rule 200001, 200004)"""
    rule_id = str(alert.get("rule", {}).get("id", ""))
    desc = alert.get("rule", {}).get("description", "").lower()

    return (
        rule_id in ["200001", "200004"] or
        "privilege escalation" in desc or
        ("sudo" in desc and "root" in desc) or
        "suspicious privileged modification" in desc
    )


def is_ssh_fail_wazuh(alert: dict) -> bool:
    """Detect SSH authentication failure (rule 100001, 5716)"""
    rule_id = str(alert.get("rule", {}).get("id", ""))
    desc = alert.get("rule", {}).get("description", "").lower()

    return (
        rule_id in ["100001", "5716"] or
        ("authentication failed" in desc and "sshd" in desc) or
        "failed password" in desc
    )


def is_ssh_success_wazuh(alert: dict) -> bool:
    """Detect successful SSH login (rule 200003)"""
    rule_id = str(alert.get("rule", {}).get("id", ""))
    desc = alert.get("rule", {}).get("description", "").lower()

    return (
        rule_id == "200003" or
        "successful ssh login" in desc or
        ("session opened" in desc and "sshd" in desc)
    )


def is_package_install_wazuh(alert: dict) -> bool:
    """Detect package installation (rule 12002)"""
    rule_id = str(alert.get("rule", {}).get("id", ""))
    desc = alert.get("rule", {}).get("description", "").lower()

    return (
        rule_id == "12002" or
        "package was installed" in desc or
        "dpkg" in desc
    )


def pretty_time(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f UTC")


# ---------- MAIN CORRELATOR ----------

def main():
    print("[INFO] Starting Enhanced Correlation Engine")
    print(f"       Watching Snort log : {SNORT_FAST_LOG}")
    print(f"       Reading Wazuh JSON: {WAZUH_ALERTS_URL}")
    print()

    # State for Snort
    snort_pos = 0
    recent_nmap_scans = []      # {time, src_ip, raw}
    recent_port_scans = []      # {time, src_ip, raw}
    recent_ssh_bruteforce = []  # {time, src_ip, raw}
    recent_reverse_shells = []  # {time, src_ip, raw}

    # State for Wazuh
    last_wazuh_ts = datetime.min.replace(tzinfo=timezone.utc)
    recent_ssh_fails = []       # list of {time, src_ip}
    recent_priv_esc = []        # list of {time, agent, desc}

    last_wazuh_poll = 0

    while True:
        now = datetime.now(timezone.utc)

        # ----- 1) Read new Snort alerts (tail) -----
        try:
            with open(SNORT_FAST_LOG, "r", errors="ignore") as f:
                f.seek(snort_pos)
                new_lines = f.readlines()
                snort_pos = f.tell()
        except FileNotFoundError:
            new_lines = []

        for line in new_lines:
            line = line.strip()
            if not line:
                continue

            src_ip = extract_first_ip(line) or "unknown"
            event = {
                "time": now,
                "src_ip": src_ip,
                "raw": line,
            }

            # Classify Snort alerts
            if is_nmap_scan_snort(line):
                recent_nmap_scans.append(event)
                print("\n[SNORT] Detected Nmap/ICMP scan:")
                print(f"  Time : {pretty_time(event['time'])}")
                print(f"  SrcIP: {event['src_ip']}")
                print(f"  Raw  : {event['raw']}")

            elif is_port_scan_snort(line):
                recent_port_scans.append(event)
                print("\n[SNORT] Detected port scan (SYN/FIN/Xmas):")
                print(f"  Time : {pretty_time(event['time'])}")
                print(f"  SrcIP: {event['src_ip']}")
                print(f"  Raw  : {event['raw']}")

            elif is_ssh_bruteforce_snort(line):
                recent_ssh_bruteforce.append(event)
                print("\n[SNORT] Detected SSH brute force:")
                print(f"  Time : {pretty_time(event['time'])}")
                print(f"  SrcIP: {event['src_ip']}")
                print(f"  Raw  : {event['raw']}")

            elif is_reverse_shell_snort(line):
                recent_reverse_shells.append(event)
                print("\n[SNORT] Detected reverse shell attempt:")
                print(f"  Time : {pretty_time(event['time'])}")
                print(f"  SrcIP: {event['src_ip']}")
                print(f"  Raw  : {event['raw']}")

        # Remove old Snort events
        max_window = max(SCAN_TO_SUDO_WINDOW, SCAN_TO_SSH_WINDOW,
                        REVERSE_SHELL_WINDOW, SSH_FAIL_WINDOW, PACKAGE_INSTALL_WINDOW)
        cutoff = now - max_window
        recent_nmap_scans = [e for e in recent_nmap_scans if e["time"] >= cutoff]
        recent_port_scans = [e for e in recent_port_scans if e["time"] >= cutoff]
        recent_ssh_bruteforce = [e for e in recent_ssh_bruteforce if e["time"] >= cutoff]
        recent_reverse_shells = [e for e in recent_reverse_shells if e["time"] >= cutoff]

        # ----- 2) Periodically pull new Wazuh alerts -----
        if (now - datetime.fromtimestamp(last_wazuh_poll, tz=timezone.utc)).total_seconds() >= WAZUH_POLL_INTERVAL:
            last_wazuh_poll = time.time()
            try:
                resp = requests.get(WAZUH_ALERTS_URL, timeout=3)
                resp.raise_for_status()
                body = resp.json()  # Directly parse JSON response
            except Exception as e:
                print(f"[WARN] Could not fetch Wazuh alerts: {e}")
                body = []

            max_ts_seen = last_wazuh_ts

            for alert in body:  # Iterate over each alert in the list
                ts_str = alert.get("timestamp")
                if not ts_str:
                    continue

                ts = parse_wazuh_timestamp(ts_str)

                # Only process new alerts
                if ts <= last_wazuh_ts:
                    continue

                if ts > max_ts_seen:
                    max_ts_seen = ts

                # Extract common fields
                agent_name = alert.get("agent", {}).get("name", "unknown")
                rule_desc = alert.get("rule", {}).get("description", "")
                src_ip = alert.get("data", {}).get("srcip", "unknown")

                # --- CORRELATION LOGIC ---

                # CORRELATION 1: Nmap/Port Scan → Privilege Escalation
                if is_sudo_or_priv_esc_wazuh(alert):
                    recent_priv_esc.append({
                        "time": ts,
                        "agent": agent_name,
                        "desc": rule_desc
                    })

                    # Check for prior Nmap scan
                    for scan in recent_nmap_scans:
                        if abs((ts - scan["time"]).total_seconds()) <= SCAN_TO_SUDO_WINDOW.total_seconds():
                            print("\n" + "="*60)
                            print("[CRITICAL] CORRELATED ATTACK: NMAP SCAN → PRIVILEGE ESCALATION")
                            print("="*60)
                            print(f"[*] Attack Timeline:")
                            print(f"    1. Nmap scan    : {pretty_time(scan['time'])} from {scan['src_ip']}")
                            print(f"    2. Priv escalation: {pretty_time(ts)} on {agent_name}")
                            print(f"[*] Time difference : {abs((ts - scan['time']).total_seconds()):.1f} seconds")
                            print(f"[*] Snort Alert     : {scan['raw']}")
                            print(f"[*] Wazuh Alert     : {rule_desc}")
                            print("="*60 + "\n")
                            break

                    # Check for prior port scan
                    for scan in recent_port_scans:
                        if abs((ts - scan["time"]).total_seconds()) <= SCAN_TO_SUDO_WINDOW.total_seconds():
                            print("\n" + "="*60)
                            print("[CRITICAL] CORRELATED ATTACK: PORT SCAN → PRIVILEGE ESCALATION")
                            print("="*60)
                            print(f"[*] Attack Timeline:")
                            print(f"    1. Port scan    : {pretty_time(scan['time'])} from {scan['src_ip']}")
                            print(f"    2. Priv escalation: {pretty_time(ts)} on {agent_name}")
                            print(f"[*] Time difference : {abs((ts - scan['time']).total_seconds()):.1f} seconds")
                            print(f"[*] Snort Alert     : {scan['raw']}")
                            print(f"[*] Wazuh Alert     : {rule_desc}")
                            print("="*60 + "\n")
                            break

                # CORRELATION 2: SSH Brute Force (Snort + Wazuh) → Success
                if is_ssh_fail_wazuh(alert):
                    recent_ssh_fails.append({"time": ts, "src_ip": src_ip})

                if is_ssh_success_wazuh(alert):
                    # Check Wazuh SSH failures
                    recent_ssh_fails[:] = [
                        f for f in recent_ssh_fails
                        if (ts - f["time"]) <= SSH_FAIL_WINDOW
                    ]

                    # Check Snort SSH brute force
                    snort_bruteforce = [
                        b for b in recent_ssh_bruteforce
                        if (ts - b["time"]) <= SCAN_TO_SSH_WINDOW
                    ]

                    if len(recent_ssh_fails) >= 3 or snort_bruteforce:
                        print("\n" + "="*60)
                        print("[CRITICAL] CORRELATED ATTACK: SSH BRUTE FORCE → SUCCESS")
                        print("="*60)
                        print(f"[*] Successful login: {pretty_time(ts)} on {agent_name}")
                        print(f"[*] Failed attempts (Wazuh): {len(recent_ssh_fails)}")
                        print(f"[*] Snort detections: {len(snort_bruteforce)}")
                        if snort_bruteforce:
                            print(f"[*] Snort alert: {snort_bruteforce[0]['raw']}")
                        print(f"[*] Wazuh alert: {rule_desc}")
                        print("="*60 + "\n")
                        recent_ssh_fails.clear()

                # CORRELATION 3: Port Scan → Reverse Shell
                if is_reverse_shell_snort:
                    for shell in recent_reverse_shells:
                        for scan in recent_port_scans:
                            if abs((shell["time"] - scan["time"]).total_seconds()) <= REVERSE_SHELL_WINDOW.total_seconds():
                                print("\n" + "="*60)
                                print("[CRITICAL] CORRELATED ATTACK: PORT SCAN → REVERSE SHELL")
                                print("="*60)
                                print(f"[*] Attack Timeline:")
                                print(f"    1. Port scan     : {pretty_time(scan['time'])} from {scan['src_ip']}")
                                print(f"    2. Reverse shell : {pretty_time(shell['time'])} from {shell['src_ip']}")
                                print(f"[*] Time difference  : {abs((shell['time'] - scan['time']).total_seconds()):.1f} seconds")
                                print(f"[*] Snort scan alert : {scan['raw']}")
                                print(f"[*] Snort shell alert: {shell['raw']}")
                                print("="*60 + "\n")

                # CORRELATION 4: Privilege Escalation → Package Install
                if is_package_install_wazuh(alert):
                    for priv in recent_priv_esc:
                        if abs((ts - priv["time"]).total_seconds()) <= PACKAGE_INSTALL_WINDOW.total_seconds():
                            print("\n" + "="*60)
                            print("[WARNING] CORRELATED ACTIVITY: PRIV ESC → PACKAGE INSTALL")
                            print("="*60)
                            print(f"[*] Activity Timeline:")
                            print(f"    1. Privilege escalation: {pretty_time(priv['time'])} on {priv['agent']}")
                            print(f"    2. Package installation: {pretty_time(ts)} on {agent_name}")
                            print(f"[*] Time difference: {abs((ts - priv['time']).total_seconds()):.1f} seconds")
                            print(f"[*] Priv esc alert : {priv['desc']}")
                            print(f"[*] Package alert  : {rule_desc}")
                            print("="*60 + "\n")
                            break

            last_wazuh_ts = max_ts_seen

        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[INFO] Correlator stopped by user")
