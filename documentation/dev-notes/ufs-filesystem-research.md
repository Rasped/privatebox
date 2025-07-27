# UFS Filesystem Research and Workarounds

## Understanding UFS

### What is UFS?
- Unix File System - native to BSD systems
- OPNsense (FreeBSD-based) uses UFS2
- Different from Linux ext4/xfs/btrfs

### Linux UFS Support Status
- **Read**: Full support (mount -t ufs)
- **Write**: NOT SUPPORTED in mainline kernel
- Reason: Complex implementation, limited demand

## Technical Details

### UFS Partition Layout in OPNsense IMG
```
Device         Start     End Sectors  Size Type
/dev/loop0p1    2048    2079      32   16K FreeBSD boot
/dev/loop0p2    2080 1048575 1046496  511M FreeBSD UFS
/dev/loop0p3 1048576 6291455 5242880  2.5G FreeBSD UFS
```

### Mount Attempts on Linux
```bash
# Read-only mount works
mount -t ufs -o ro,ufstype=ufs2 /dev/loop0p3 /mnt

# Write mount fails
mount -t ufs -o rw,ufstype=ufs2 /dev/loop0p3 /mnt
# Error: UFS write not supported
```

## Workaround Options

### 1. FreeBSD VM Method
**Most Reliable**
```bash
# On FreeBSD:
mdconfig -a -t vnode -f opnsense.img
mount /dev/md0p3 /mnt
# Full read/write access
cp config.xml /mnt/conf/
umount /mnt
mdconfig -d -u md0
```

### 2. guestfs Tools
**Unconfirmed**
- libguestfs claims BSD support
- May support UFS writes
- Requires testing
```bash
guestmount -a opnsense.img -m /dev/sda3 --rw /mnt
```

### 3. Convert UFS to ISO
**One-way conversion**
```bash
# Mount read-only
mount -t ufs -o ro,ufstype=ufs2 opnsense.img /mnt
# Copy all files
cp -a /mnt/* /tmp/opnsense-files/
# Create new ISO
mkisofs -o custom.iso /tmp/opnsense-files/
```

### 4. In-Place Binary Edit
**Extremely risky**
- Find config.xml location in IMG
- Binary edit if same size
- High corruption risk

### 5. FUSE-UFS
**Experimental**
- User-space UFS implementation
- May have write support
- Not production ready

## Platform-Specific Solutions

### macOS
- Full UFS read/write support
- Can modify IMG files directly
- Requires macOS system

### FreeBSD/TrueNAS
- Native UFS support
- Best option for modifications
- Could run in VM

### Windows
- No native UFS support
- Requires third-party tools
- Not recommended

## Recommended Approach

**For production use:**
1. Spin up minimal FreeBSD VM
2. Transfer IMG file
3. Mount and modify
4. Transfer back

**Alternative:**
- Abandon IMG modification
- Use different deployment method
- Two-ISO or post-boot config

## Tools Summary

| Tool | Read | Write | Platform | Reliability |
|------|------|-------|----------|-------------|
| Linux kernel | ✓ | ✗ | Linux | High |
| FreeBSD | ✓ | ✓ | FreeBSD | High |
| macOS | ✓ | ✓ | macOS | High |
| guestfs | ✓ | ? | Linux | Unknown |
| FUSE-UFS | ✓ | ? | Linux | Low |

## Conclusion
UFS write support on Linux is the core blocker. Solutions require either:
- Different OS (FreeBSD/macOS)
- Different approach (avoid IMG modification)
- Experimental tools (risky)