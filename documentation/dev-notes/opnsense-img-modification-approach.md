# OPNsense IMG Modification Approach

## Overview
Attempt to modify pre-installed OPNsense IMG files to include custom configuration.

## IMG File Types

### VGA IMG
- Pre-installed OPNsense system
- Ready to boot when written to disk
- Contains UFS filesystem
- ~600MB compressed, ~3GB uncompressed

### Serial IMG
- Same as VGA but configured for serial console
- Also contains UFS filesystem

### Nano IMG  
- Embedded version for small devices
- Cannot be installed to hard disk
- MBR boot (not UEFI)

## The UFS Challenge

### Problem
- IMG files contain UFS (Unix File System)
- Linux kernel has **read-only** UFS support
- Cannot modify config.xml directly on Linux

### What Happens
```bash
# This works - mounts read-only
mount -t ufs -o ro,ufstype=ufs2 /dev/loop0p3 /mnt

# This fails - no write support
mount -t ufs /dev/loop0p3 /mnt
# Error: UFS write support not available
```

## Attempted Solutions

### 1. Direct Modification (Failed)
- Mount IMG on Linux
- Try to modify /conf/config.xml
- Blocked by read-only UFS

### 2. Loop Device Approach (Failed)
```bash
losetup /dev/loop0 opnsense.img
kpartx -av /dev/loop0
# Can see partitions but can't write to UFS
```

### 3. NBD (Network Block Device) (Failed)
```bash
qemu-nbd -c /dev/nbd0 opnsense.img
# Same issue - UFS is read-only
```

## Why It Would Be Ideal
- IMG boots directly - no installation needed
- Pre-configured system ready to use
- Single file deployment
- No console interaction if config is right

## Potential Workarounds

### 1. FreeBSD VM
- Create minimal FreeBSD VM
- Use it to mount and modify IMG
- FreeBSD has full UFS read/write support

### 2. guestfs Tools
- libguestfs might support UFS writes
- Not confirmed to work

### 3. Two-Stage Process
- Boot IMG as-is
- Use automation to apply config after boot
- Requires network access to VM

### 4. Convert to Different Format
- Extract files from IMG while mounted read-only
- Repackage as ISO or other format
- Loses pre-installed advantage

## Conclusion
IMG modification blocked by Linux's UFS limitations. Need either:
- FreeBSD system for modifications
- Different approach entirely
- Post-boot configuration method