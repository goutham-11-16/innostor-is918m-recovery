# Innostor IS918M (C205) USB Flash Drive Hardware Write-Protection Recovery Guide

A complete, production-grade guide and diagnostic toolkit for diagnosing, unlocking, and restoring USB 3.0 flash drives afflicted by the infamous **Hardware SCSI Data Protect / Write-Protected Lock**, specifically targeted at devices using the **Innostor / ASolid IS918M (C205)** controller and **Samsung 3D V-NAND TLC**.

---

## 📌 Case Profile: The Exact Hardware Specification

This procedure was documented on an **Amazon Basics 64GB USB 3.0 Flash Drive** (Metallic Silver unibody):

| Component / Property | Identified Value |
| :--- | :--- |
| **Product Model** | Amazon Basics 64GB USB 3.0 Metallic Flash Drive |
| **USB VID / PID** | `24A9:205A` |
| **USB Specification** | USB 3.2 Gen 1 SuperSpeed (5 Gbps), BOT (`usb-storage`) |
| **USB Controller ASIC** | **Innostor / ASolid IS918M** (`C205` / Project `18002` / `BWC205A`) |
| **NAND Manufacturer** | **Samsung Electronics** (`0xEC`) |
| **NAND Part Number** | Samsung `K9AHGD8H0B` (Toggle DDR 3D V-NAND TLC) |
| **NAND Flash ID** | `EC, 5E, 98, AF, 84, CD, 00` (CE: 1, 2-Plane) |
| **Recovered Capacity** | **69.4 GB** (69,391,613,952 bytes / 64.63 GiB) |
| **Default Filesystem** | `exFAT` (128 KiB cluster) |

---

## 🧠 Root Cause: Why Do These Drives Suddenly Lock Up?

When this drive encounters an unclean disconnect or power interruption during an active Flash Translation Layer (FTL) journal metadata write, the controller detects a **dirty journal state in internal NVRAM**.

To prevent silent data corruption, the **IS918M firmware engages a hardware write-protect latch**:
1. In response to SCSI `MODE SENSE (6)` commands, the controller returns the **`WP` (Write Protect) bit set to 1** in byte 2 of the mode parameter header (`0x80`).
2. Operating systems (Linux, Windows, macOS) read this bit and immediately set the block device to read-only.
3. Any raw SCSI `WRITE (10)` command sent directly to the device is rejected at the firmware level with:
   - **SCSI Status:** `Check Condition (0x02)`
   - **Sense Key:** `Data Protect (0x07)`
   - **ASC / ASCQ:** `0x27 / 0x00` (`Write protected`)

### Why Common Software "Fixes" Fail
- **`diskpart -> attributes disk clear readonly`**: Fails. Diskpart only clears Windows software registry flags; the underlying SCSI driver re-queries the drive and re-latches read-only.
- **Registry `StorageDevicePolicies`**: Fails. This controls OS-level policies, not USB target hardware flags.
- **Linux `blockdev --setrw /dev/sdX`**: Fails. The Linux `sd` kernel module queries `MODE SENSE` on every probe and immediately forces `ro=1`.
- **`dd`, `mkfs`, `fdisk`**: Fail with `Input/output error` or `Read-only file system`.

---

## 🔍 Phase 1: Linux (Ubuntu) Diagnostics

Run the bundled diagnostic script to confirm if your drive has hardware SCSI write protection:

```bash
chmod +x scripts/diagnose_scsi_wp.sh
sudo ./scripts/diagnose_scsi_wp.sh /dev/sdX
```
*(Replace `/dev/sdX` with your drive node, e.g., `/dev/sda` or `/dev/sdb`)*

### Manual Diagnostic Commands

1. **Verify USB Enumeration & VID/PID:**
   ```bash
   lsusb -d 24a9:205a -v
   ```
2. **Inspect Kernel Mode Sense Headers:**
   ```bash
   sudo dmesg | grep -E "sd [0-9]|Write Protect"
   ```
   *Hardware-locked drives output:*
   ```text
   [sda] Write Protect is on
   [sda] Mode Sense: 23 00 80 00
   ```
   *(Notice `80` in byte 2: the `WP=1` bit is set).*

3. **Check SCSI Mode Header with `sg3-utils`:**
   ```bash
   sudo apt install sg3-utils
   sudo sg_modes -v /dev/sdX
   ```

4. **Verify Raw SCSI Rejection (Bypassing OS Filesystem):**
   ```bash
   # Attempt writing 1 sector directly to LBA 0 via raw SCSI command
   sudo sg_raw /dev/sgX 2a 00 00 00 00 00 00 00 01 00 -s 512 -i /dev/zero
   ```
   *If the hardware is locked, it returns:*
   ```text
   Sense key: Data Protect [0x7]
   Additional sense: Write protected [0x27, 0x00]
   ```

---

## ⚠️ Phase 2: Diagnostic Traps & Why Generic Tools Fail

1. **ChipGenius & Flash Drive Information Extractor (FDIE) report "Unknown":**
   - Innostor IS918M / C205 controllers with newer firmware revisions do not respond to generic public vendor inquiry pass-throughs. ChipGenius v2.35 and FDIE v9.4 both fail to extract the NAND ID or controller name.
2. **Wine on Linux Does Not Work for Flashing:**
   - The Innostor Mass Production Tool relies on Windows native `SetupAPI` and `GUID_DEVINTERFACE_USB_HUB` enumeration to interact directly with the USB physical hub topology. Under Wine, this results in `[HUBInfo] Count=0` and the tool will fail to see the drive.
   - **Requirement:** Factory recovery **MUST** be performed in a native Windows environment or a Windows Virtual Machine with direct USB passthrough.

---

## 🛠️ Phase 3: Mass Production Tool Recovery (Windows)

### Prerequisites
1. Download **`IS918MPTool GA 230908C`** (or newer IS918M GA release).
2. Connect the write-protected USB drive directly to a USB 3.0 or 2.0 port on a Windows machine.

### Step-by-Step Procedure

1. **Launch the Factory Tool:**
   - Run `IS918MPTool.exe` as Administrator.
2. **Select Product Mode:**
   - A dialog will appear asking you to choose between:
     - `Semi-Finished Product`
     - `Test Product`
   - **Select `Semi-Finished Product`** (This maps to the `C205` ASIC core).
3. **Verify Passive Detection:**
   - Plug in the drive (or click `Refresh`).
   - A port cell (e.g., `E:`) will turn green/highlighted.
   - The tool will automatically read and display:
     - **Flash Type:** `Samsung K9AHGD8H0B` (or your specific NAND model)
     - **Flash ID:** `EC, 5E, 98, AF, 84, CD, 00`
     - **CE Count:** `1 (2P)`
4. **Configure Recovery Settings:**
   - Click **`Setting`** (Password is usually empty or `IS918`).
   - Configure the following critical options:
     - **Optimize:** `Capacity Optimize` (or `Speed Optimize`)
     - **Format Type:** `High Level Format`
     - **Erase Mode:** `Erase All + MP`
     - **Scan Mode:** `Auto Check`
   - Save and return to the main window.
5. **Execute Factory Flash:**
   - Press the **`Space`** key or click **`Start (MP)`**.
   - The tool will low-level format the NAND, re-map bad blocks, burn fresh FTL tables, and write a clean serial number.
   - **Duration:** Approximately **40 to 60 seconds**.
6. **Result:**
   - The cell will turn bright green displaying **`PASS (S)`**.
   - Note the reported bad block count (e.g., `8 / 1458` bad blocks).
   - Safe remove and unplug the drive.

---

## 🚀 Phase 4: Linux Post-Recovery Partitioning & Verification

Once factory initialization finishes, plug the drive back into Linux.

### 1. Confirm Hardware Lock Is Cleared
```bash
sudo dmesg | tail -n 15
```
Output must now report:
```text
sd 0:0:0:0: [sda] Write Protect is off
sd 0:0:0:0: [sda] Mode Sense: 23 00 00 00
```
*(Notice `00` in byte 2: the Write Protect bit is completely cleared!)*

### 2. Create GPT Partition & Format exFAT
```bash
# Wipe legacy remnants
sudo wipefs -a /dev/sdX

# Create fresh partition
sudo parted -s /dev/sdX mklabel gpt
sudo parted -s /dev/sdX mkpart primary 2048s 100%

# Format as exFAT
sudo mkfs.exfat -n "USB_RECOVERED" /dev/sdX1
```

### 3. Run Throughput & Integrity Verification
Run the bundled verification script:
```bash
chmod +x scripts/verify_drive.sh
./scripts/verify_drive.sh /run/media/$USER/USB_RECOVERED 50
```
This performs a 50 MB pseudorandom write with `conv=fsync`, drops Linux page caches, reads back the file, and validates SHA-256 integrity.

---

## 📊 Why Does the Filesystem Show 69 GB on a 64 GB Drive?

Many users are surprised to see **69.4 GB** after recovering an Amazon Basics 64 GB flash drive:

$$\frac{69,391,613,952 \text{ bytes}}{1,000,000,000} \approx \mathbf{69.39 \text{ GB (Decimal)}}$$

- **Commercial Retail Limit:** Retail vendors cap drives at $64,000,000,000$ bytes to provide uniform retail packaging, hiding the rest as over-provisioning reserve.
- **Raw NAND Silicon:** The Samsung `K9AHGD8H0B` die actually contains over $69 \times 10^9$ bytes of raw silicon.
- **`Capacity Optimize` Setting:** When we flashed using `Capacity Optimize` with only 8 bad blocks out of 1,458 (>99.4% healthy silicon), the factory tool mapped **all healthy physical blocks** directly into user storage, giving you **~5.4 GB of bonus usable space**!

---

## ⚡ Performance Benchmark Summary

Empirical results captured via USB 3.0 SuperSpeed (5 Gbps) under Linux Kernel 7.0:

| Metric | Result |
| :--- | :--- |
| **Sustained Sequential Write** | **76.0 MB/s** |
| **Sustained Sequential Read** | **96.4 MB/s** |
| **Data Integrity Check** | 100% Match (Zero Bit Flips) |
| **NAND Health Reserve** | 99.45% Pristine |

---

## 🛡️ Best Practices to Prevent Re-Locking

1. **Always Safely Eject:** The Innostor FTL controller latches the hardware write protect bit if removed while write buffers are uncommitted. Always run `sync` and unmount/eject before unplugging.
2. **Keep a Backup of `IS918MPTool GA`:** Keep the MPTool archive handy in case an accidental disconnect ever triggers the FTL lock again.

---

## 📄 License
This guide and diagnostic scripts are licensed under the [MIT License](LICENSE).
