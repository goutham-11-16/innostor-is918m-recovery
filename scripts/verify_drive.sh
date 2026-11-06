#!/usr/bin/env bash
# ==============================================================================
# USB Flash Drive Throughput & Verification Benchmark
# Author: Goutham & Antigravity
# Description:
#   Performs a non-destructive or mounted filesystem write/read throughput test,
#   flushes OS dirty pages with sync, and checks SHA256 integrity.
# ==============================================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/mounted/usb [test_size_mb]"
    echo "Example: $0 /run/media/goutham/00D0-0810 100"
    exit 1
fi

MOUNT_DIR="$1"
TEST_SIZE_MB="${2:-50}"
TEST_FILE="$MOUNT_DIR/.verify_test_$(date +%s).tmp"

if [[ ! -d "$MOUNT_DIR" ]]; then
    echo "[-] Error: Directory $MOUNT_DIR does not exist or is not mounted."
    exit 1
fi

echo "=========================================================="
echo " USB Flash Drive Benchmark: $MOUNT_DIR"
echo " Test File Size: ${TEST_SIZE_MB} MB"
echo "=========================================================="

echo "[*] Step 1: Performing direct write test with fsync..."
START_WRITE=$(date +%s.%N)
dd if=/dev/urandom of="$TEST_FILE" bs=1M count="$TEST_SIZE_MB" conv=fsync status=progress
END_WRITE=$(date +%s.%N)

WRITE_TIME=$(echo "$END_WRITE - "$START_WRITE | bc)
WRITE_SPEED=$(echo "scale=2; $TEST_SIZE_MB / $WRITE_TIME" | bc)
echo ""
echo "[+] Write Test Finished: ${TEST_SIZE_MB} MB in ${WRITE_TIME}s (${WRITE_SPEED} MB/s)"
echo ""

echo "[*] Step 2: Calculating SHA-256 hash of written file..."
ORIGINAL_HASH=$(sha256sum "$TEST_FILE" | awk '{print $1}')
echo "    Original Hash: $ORIGINAL_HASH"
echo ""

echo "[*] Step 3: Dropping Linux page caches to force physical read..."
if command -v pkexec >/dev/null 2>&1; then
    pkexec sh -c "echo 3 > /proc/sys/vm/drop_caches" || echo "[-] Cache drop skipped (non-fatal)."
elif [[ $EUID -eq 0 ]]; then
    echo 3 > /proc/sys/vm/drop_caches
fi

echo "[*] Step 4: Performing direct read throughput test..."
START_READ=$(date +%s.%N)
dd if="$TEST_FILE" of=/dev/null bs=1M status=progress
END_READ=$(date +%s.%N)

READ_TIME=$(echo "$END_READ - "$START_READ | bc)
READ_SPEED=$(echo "scale=2; $TEST_SIZE_MB / $READ_TIME" | bc)
echo ""
echo "[+] Read Test Finished: ${TEST_SIZE_MB} MB in ${READ_TIME}s (${READ_SPEED} MB/s)"
echo ""

echo "[*] Step 5: Verifying read integrity (re-hashing)..."
VERIFY_HASH=$(sha256sum "$TEST_FILE" | awk '{print $1}')
echo "    Read Hash:     $VERIFY_HASH"

if [[ "$ORIGINAL_HASH" == "$VERIFY_HASH" ]]; then
    echo ""
    echo "[✔] SUCCESS: Hashes match perfectly! Zero silent corruption."
else
    echo ""
    echo "[✘] ERROR: Hashes do NOT match! NAND corruption detected."
    rm -f "$TEST_FILE"
    exit 2
fi

rm -f "$TEST_FILE"
echo "[+] Temporary test file cleaned up."
echo "=========================================================="
echo " Benchmark & Verification Completed Successfully."
echo "=========================================================="
