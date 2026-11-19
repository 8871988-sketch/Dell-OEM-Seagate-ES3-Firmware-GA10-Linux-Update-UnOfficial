# Dell-OEM Seagate Constellation ES.3 (ST1000NM0033 and family): firmware update to GA10 on a non-Dell Linux server

**Unofficial community guide.** No firmware is distributed here: you download the original package from Dell yourself.

Languages: **English** | [Українська](README.uk.md) | [Deutsch](README.de.md)

---

## What this is about

Dell-branded Seagate Constellation ES.3 SATA drives (`Add. Product Id: DELL(tm)`, firmware `GA0x`) often end up in non-Dell machines: rented dedicated servers, refurbished hardware, home labs. Dell publishes a newer firmware, **GA10**, for these drives, but:

- Dell's update package refuses to run on non-Dell hardware (`Can't open IPMI device`, "not compatible with your system configuration").
- Seagate's own firmware (`SN0x`) is made for retail drives and must not be put on Dell-OEM drives.

This guide shows how to take the firmware image out of Dell's package, remove the Dell wrapper header, verify the result, and flash it with plain `hdparm`. Every command below was run on a real server.

## Tested configuration

| Item | Value |
|---|---|
| Server | HP ProLiant DL120 G7, onboard SATA controller (drives appear as plain `/dev/sdX`) |
| OS | CentOS 7, kernel 3.10.0-1062 (x86_64), Plesk |
| Tools | hdparm 9.43, smartmontools 7.0 |
| Drives | 4 × Seagate `ST1000NM0033-9ZM173`, Dell OEM |
| Firmware before | `GA06` (2 drives), `GA0A` (2 drives) |
| Firmware after | `GA10` (all 4 drives) |
| Date | 2026-11-19 |

Result: all four drives accepted the image on the first attempt. The new revision was active immediately, with no reboot and no power cycle. Three drives were flashed unmounted; the system disk (boot and root) was flashed while the OS was running from it. Afterwards SMART health was `PASSED` and short self-tests completed without error on all four.

## Is this guide for your drive?

Run `smartctl -i /dev/sdX` (or `scripts/list-drives.sh`). The guide applies only if **all** of this is true:

1. `Device Model` is one of
   `ST4000NM0033-9ZM170`, `ST3000NM0033-9ZM178`, `ST2000NM0033-9ZM175`, `ST1000NM0033-9ZM173`, `ST500NM0003-9ZM172`
2. `Add. Product Id` is `DELL(tm)`
3. `Firmware Version` starts with `GA0` (for example `GA06`, `GA0A`, `GA0D`, `GA0F`)
4. The drive is attached directly to a SATA/AHCI port, so `hdparm` can talk to it

Only `ST1000NM0033-9ZM173` was actually tested. The other four models are listed in the header of the same firmware file and on Dell's download page, but nobody here has flashed them.

The guide does **not** apply to:

| Drive | What to do instead |
|---|---|
| Dell drives with `GA6x` firmware (the 6 Gb/s variant) | Dell lists `GA6E` for these, which is a different package (Driver ID `72RV5`). Do not flash GA10 on them. |
| Retail drives with `SN0x` firmware | Use Seagate's own firmware download. |
| SAS models (`ST…NM0023`, firmware `GSxx`) | Different firmware and different flashing tools. |
| Drives behind a hardware RAID controller (PERC, Smart Array, MegaRAID) | Not tested. `hdparm` usually cannot reach such drives. |

## Why update at all

- Dell's release notes for GA10 describe a fix for inaccurate counting of SMART seek errors, which could trip SMART unexpectedly, plus general robustness improvements.
- Dell KB article 000179687 lists GA10 as the recommended firmware for the 3 Gb/s SATA variants of these drives, to prevent premature failures.

If your drives work and you do not want any risk, leaving them alone is a perfectly valid choice.

## Warnings

- This is **not** an official Dell or Seagate procedure. You do it at your own risk. A failed or wrong firmware download can make a drive permanently unusable.
- **Never** flash the `.fwh` file as it is. It must be converted to `.lod` first (step 4). A report on the HDD Guru forum describes a drive of the same family that was destroyed by sending the file with the Dell header still attached.
- Never mix firmware families: `GA0x` → GA10 only. No `SN0x`, no `GA6x`.
- Have a current backup. Flash **one drive at a time** and check it before touching the next one.
- Do not interrupt the download, do not reboot and do not cut power while `hdparm` is running.
- For the system disk, make sure you have out-of-band access (iLO, IPMI, or the provider's power control) before you start.

## Step by step

All commands run as `root`.

### 0. Prerequisites

```bash
yum install -y hdparm smartmontools curl      # Debian/Ubuntu: apt install hdparm smartmontools curl
```

CentOS 7 is end-of-life. If `yum` cannot find a mirror, point it at `vault.centos.org` first.

### 1. Identify the drives

```bash
lsblk -o NAME,SIZE,MODEL,REV,MOUNTPOINT
smartctl -i /dev/sda
```

Relevant lines of the `smartctl` output:

```
Model Family:     Seagate Constellation ES.3
Device Model:     ST1000NM0033-9ZM173
Add. Product Id:  DELL(tm)
Firmware Version: GA06
SATA Version is:  SATA 3.0, 3.0 Gb/s (current: 3.0 Gb/s)
```

### 2. Download Dell's package and verify it

Dell Driver ID **HPG73**, version "GA10, A00", released 10 May 2016.

```bash
mkdir -p /root/ga10 && cd /root/ga10
curl -L -A "Mozilla/5.0" -O https://dl.dell.com/FOLDER03579122M/1/Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
sha256sum Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
```

Expected SHA-256 (as published on Dell's download page):

```
3d2efefa03b8942cdee4bca30012bed69badb611b79ebce20d7642601f698999
```

Stop here if the checksum is different.

### 3. Extract the package without installing it

```bash
chmod +x Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN
./Serial-ATA_Firmware_HPG73_LN_GA10_A00.BIN --extract ./extracted
ls -l extracted/payload/
```

Expected:

```
Successfully extracted to ./extracted
-rwxr-xr-t 1 root root 1691952 Feb 19  2016 GA10.fwh
```

### 4. Convert `GA10.fwh` to `GA10.lod`

`GA10.fwh` is a Seagate LOD image with a 304-byte Dell header in front of it. The header has to go.

**With the script** (recommended, it runs three independent checks and refuses to write anything if one fails):

```bash
cd /root
git clone https://github.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial.git
cd Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial
./scripts/fwh2lod.sh -m ST1000NM0033-9ZM173 /root/ga10/extracted/payload/GA10.fwh /root/ga10/GA10.lod
```

Use your own model after `-m`. Without `git`, fetch the single file instead:
`curl -LO https://raw.githubusercontent.com/8871988-sketch/Dell-OEM-Seagate-ES3-Firmware-GA10-Linux-Update-UnOfficial/main/scripts/fwh2lod.sh && chmod +x fwh2lod.sh`

Expected output (shortened):

```
Firmware revision : GA10
Model entries     : 5
   - ST4000NM0033-9ZM170
   - ST3000NM0033-9ZM178
   - ST2000NM0033-9ZM175
   - ST1000NM0033-9ZM173
   - ST500NM0003-9ZM172
Dell header       : 304 bytes (0x130)
LOD image         : 1691648 bytes
Check 1/3         : length is a multiple of 512            OK
Check 2/3         : LOD header checksum                    OK
Check 3/3         : stored length equals real length       OK
SHA-256           : 6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625
Known image       : yes - identical to the GA10 image tested in this guide
```

**By hand** (exactly what was done on the test server):

```bash
cd /root/ga10
dd if=extracted/payload/GA10.fwh of=GA10.lod bs=304 skip=1
stat -c %s GA10.lod                      # must print 1691648
od -An -tu4 -j36 -N4 GA10.lod            # must print 1691648
od -An -v -tu2 -N64 GA10.lod | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s%65536}'   # must print 0
```

If any of the three numbers is different, do not continue. Why these checks work is explained in [docs/fwh-header-format.md](docs/fwh-header-format.md).

**Compare the checksum.** Both ways produce the same file, byte for byte. This is the image that was flashed on the test server:

```bash
sha256sum /root/ga10/GA10.lod
```

```
6a261b8bab566d7f014d2dd49f72f65b089d3b322348c69029545a7d18422625  /root/ga10/GA10.lod
```

A different value means your file is not the image this guide was tested with. Do not flash it.

### 5. Flash a drive that is not in use

Start with the least important drive (an empty or spare one), then do the others one by one.

```bash
DEV=/dev/sdb                                   # the drive to flash

lsblk -f $DEV                                  # check what is on it
umount /mountpoint                             # unmount every mounted partition of this drive
hdparm -I $DEV | grep -i microcode             # must list DOWNLOAD_MICROCODE

hdparm --fwdownload /root/ga10/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive $DEV
sleep 15

smartctl -i $DEV | grep -E 'Serial|Firmware'   # expect: Firmware Version: GA10
smartctl -H $DEV                               # expect: PASSED
```

What `hdparm` prints during a successful download:

```
/dev/sdb:
fwdownload: xfer_mode=3 min=1 max=1 size=512
............................................................ (many dots) ... Done.
```

Then mount the file systems again and check that the data is readable.

If `umount` says `target is busy`, do not flash. Find the process with `fuser -vm /mountpoint` first.

### 6. Flash the system disk (optional, read first)

The system disk cannot be unmounted. There are two ways:

- **Online**, while the OS runs from the disk. This is what was done on the test server, and it is also how Dell's own package works on a Dell machine.
- **From a rescue system**, which needs a reboot. On a server with a very long uptime the reboot can be the bigger risk.

Before an online flash: flash and verify all other drives first, make a fresh backup, and confirm that you can reach the machine out-of-band. The worst case is that the disk hangs while it activates the new firmware and the server needs a forced reboot.

The image is copied to RAM, and `nohup` keeps the download running if the SSH session drops:

```bash
cp /root/ga10/GA10.lod /dev/shm/ && cmp /root/ga10/GA10.lod /dev/shm/GA10.lod && echo OK
sync
nohup hdparm --fwdownload /dev/shm/GA10.lod --yes-i-know-what-i-am-doing --please-destroy-my-drive /dev/sda > /dev/shm/sda-fw.log 2>&1 &
wait; tail -c 200 /dev/shm/sda-fw.log          # must end with "Done."

smartctl -i /dev/sda | grep -E 'Serial|Firmware'
smartctl -H /dev/sda
touch /root/rw-test && rm -f /root/rw-test && echo "root file system is writable"
```

Do not start the download if `cmp` does not print `OK`.

### 7. Final checks

Replace `a b c d` with the letters of your own drives.

```bash
for d in a b c d; do smartctl -i /dev/sd$d | grep -E 'Serial|Firmware'; done
dmesg | grep -iE 'ata[0-9]+|I/O error' | tail

for d in a b c d; do smartctl -t short /dev/sd$d >/dev/null; done
sleep 150
for d in a b c d; do smartctl -l selftest /dev/sd$d | sed -n '6,7p'; done   # expect: Completed without error

rm -f /dev/shm/GA10.lod /dev/shm/sda-fw.log
```

Notes:

- No reboot is needed. `lsblk` and the boot messages in `dmesg` keep showing the old revision until the next reboot, because the kernel cached it. `smartctl -i` asks the drive directly and shows the real one.
- Keep `GA10.lod`. If a drive is ever replaced with the same model on old firmware, you will need it again.

## Troubleshooting

| Symptom | Meaning / what to do |
|---|---|
| Running the `.BIN` prints `Can't open IPMI device` | Expected on non-Dell hardware. Use `--extract` (step 3). |
| `hdparm: command not found` | Install it (step 0). Nothing was written to the drive. |
| `file size (...) not a multiple of 512` from hdparm | The header was not removed correctly. Redo step 4. |
| No `DOWNLOAD_MICROCODE` line in `hdparm -I` | The drive is not reachable for firmware download (RAID controller, USB bridge). Do not continue. |
| `umount: target is busy` | Something uses the file system. `fuser -vm /mountpoint`, stop it, then unmount. |
| hdparm reports an error, or the revision is still old after `Done.` | Do **not** repeat the command blindly. Check `dmesg`. The drive may need a full power cycle to activate the firmware. |
| `fwh2lod.sh` stops with a failed check | The file has a layout this guide does not know. Do not flash it. |

## How the `.fwh` file is built

See [docs/fwh-header-format.md](docs/fwh-header-format.md) for the header layout, a hex dump, and the reasoning behind the 304 bytes.

## References

- Dell download page for GA10, Driver ID HPG73: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=hpg73>
- Dell KB 000179687, premature failures on Seagate Megalodon/Makara drives: <https://www.dell.com/support/kbdoc/en-us/000179687/premature-failures-observed-on-seagate-megalodon-makara-sas-sata-drives-firmware-update-required-to-prevent-premature-failures>
- Dell download page for GA6E (6 Gb/s variant), Driver ID 72RV5: <https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=72rv5>
- HDD Guru forum, "Extract .LOD file (Seagate) from .FWH file (Dell)": <https://forum.hddguru.com/viewtopic.php?f=13&t=45143>
- HDD Guru forum, "Seagate SAS Firmware ST2000NM0023" (drive lost after flashing with the Dell header): <https://forum.hddguru.com/viewtopic.php?f=13&t=39135>
- HDD Guru forum, "ST2000NM0011 Firmware update over hdparm": <https://forum.hddguru.com/viewtopic.php?t=38362>
- Blog post on the same method for the older ST2000NM0011 (PA09), in German: <https://hilfetisch.wordpress.com/2019/05/05/dell-seagate-constellation-st2000nm0011-st1000nm0011-st500nm0011-firmwareupgrade-pa08-pa09/>

## Contributing

Reports are welcome, successful or not. Please open an issue with: server model, SATA controller, OS and kernel, hdparm version, exact drive model, firmware before and after, and whether the drive was mounted.

## License and disclaimer

Text and scripts are released under the [MIT License](LICENSE). The firmware itself belongs to Dell and Seagate and is not part of this repository.

This project is not affiliated with Dell, Seagate or HP. Everything here is provided without any warranty. You are responsible for your own hardware and data.
