# OPNsense Automated Deployment Approaches Overview

## Goal
Achieve 100% hands-off OPNsense deployment on Proxmox with:
- Pre-configured static IP (192.168.1.69/24)
- SSH access enabled
- No manual console interaction

## Deployment Approaches Summary

### 1. Two-ISO Approach (Most Promising)
**Status**: Not yet attempted  
**Concept**: Use OPNsense Importer feature with separate config ISO
- Main ISO: Standard OPNsense DVD ISO
- Config ISO: Contains `/conf/config.xml`
- OPNsense Importer reads config during boot

### 2. ISO Remastering (Current Attempt)
**Status**: Partially working - boots but doesn't install  
**Concept**: Embed config.xml directly in OPNsense ISO
- Modify ISO to include config at `/usr/local/etc/config.xml`
- Problem: DVD ISO is live system, not installer

### 3. IMG Modification
**Status**: Blocked by UFS read-only limitation  
**Concept**: Modify pre-installed IMG file
- IMG contains ready-to-run OPNsense system
- Cannot modify due to Linux UFS limitations

### 4. UFS Workarounds
**Status**: Research phase  
**Concept**: Various methods to work with UFS filesystem
- FreeBSD VM for modifications
- guestfs tools
- Conversion approaches

## Key Discoveries

1. **OPNsense Image Types**:
   - **DVD ISO**: Live system with manual installer
   - **VGA IMG**: Pre-installed system for USB/disk
   - **Serial IMG**: Same as VGA but serial console
   - **Nano IMG**: Embedded, can't install to disk

2. **OPNsense Importer**:
   - Since v22.1.7: Supports ISO9660 filesystem
   - Reads from `/conf/config.xml` on secondary media
   - Runs before live environment loads
   - Press any key during boot to activate

3. **UFS Filesystem Issue**:
   - Linux has read-only UFS support
   - FreeBSD has full read/write support
   - Major blocker for IMG modification approach

## Recommendation

The **Two-ISO Approach** appears most viable because:
- Uses native OPNsense features
- No filesystem modification needed
- Supports virtualization environments
- One config ISO can serve multiple deployments

See individual approach documents for detailed implementation notes.