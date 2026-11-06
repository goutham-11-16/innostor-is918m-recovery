#!/usr/bin/env bash
# ==============================================================================
# Linux SCSI & Hardware Write-Protection Diagnostic Tool
# Author: Goutham & Antigravity
# Description:
#   Performs low-level SCSI queries and checks whether a USB flash drive's
#   write protection is software-based (OS/filesystem) or locked by the
#   controller hardware (SCSI MODE SENSE Write Protect bit / Data Protect sense).
# ==============================================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/sda"
    exit 1
fi

DEVICE="$1"

if [[ ! -b "$DEVICE" ]]; then
    echo "[-] Error: $DEVICE is not a valid block device."
    exit 1
fi

echo "=========================================================="
echo " [1] Block Device & Operating System Flags"
echo "=========================================================="
lsblk -o NAME,SIZE,RO,RM,MODEL,VENDOR,TRAN "$DEVICE"
echo ""

RO_FLAG=$(blockdev --getro "$DEVICE")
echo "[*] Kernel blockdev read-only status (RO): $RO_FLAG"
if [[ "$RO_FLAG" -eq 1 ]]; then
    echo "    -> Kernel treats this block device as READ-ONLY."
else
    echo "    -> Kernel treats this block device as READ-WRITE."
fi
echo ""

echo "=========================================================="
echo " [2] USB Bus & Controller Topology"
echo "=========================================================="
udevadm info --query=property --name="$DEVICE" | grep -E "ID_VENDOR|ID_MODEL|ID_REVISION|ID_SERIAL|ID_BUS|ID_USB" || true
echo ""

echo "=========================================================="
echo " [3] SCSI Mode Parameter Header (Hardware Write Protect Bit)"
echo "=========================================================="
if command -v sg_modes >/dev/null 2>&1; then
    echo "[*] Querying SCSI MODE SENSE (6)..."
    MODE_HEX=$(sg_modes -v "$DEVICE" 2>&1 || true)
    echo "$MODE_HEX"
    echo ""
    if echo "$MODE_HEX" | grep -q "WP=1"; then
        echo "[!] CRITICAL: SCSI Mode parameter header has WP=1 (Write Protect bit is set)."
        echo "    This confirms FIRMWARE / HARDWARE level write protection."
        echo "    Software commands (e.g. 'blockdev --setrw', 'hdparm -r0') will NOT work."
    elif echo "$MODE_HEX" | grep -q "WP=0"; then
        echo "[+] SCSI Mode parameter header has WP=0 (Hardware Write Protect bit is clear)."
    fi
else
    echo "[-] Warning: 'sg3-utils' not installed. Install via: sudo apt install sg3-utils"
fi
echo ""

echo "=========================================================="
echo " [4] Kernel Log Diagnostic Summary"
echo "=========================================================="
DEV_NAME=$(basename "$DEVICE")
dmesg | grep -E "$DEV_NAME|Write Protect" | tail -n 10 || true
echo ""
echo "=========================================================="
echo " Diagnostics complete."
echo "=========================================================="
