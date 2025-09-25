# PrivateBox Recovery System

## Overview

PrivateBox includes a built-in recovery system that provides factory reset capability while preserving unique installation passwords. This creates a true appliance experience - users can always recover to a known-good state without losing their credentials.

## Design Goals

- **Simple**: One-button factory reset like a router
- **Secure**: Passwords encrypted and inaccessible from main OS
- **Offline**: No network required for recovery
- **Physical-only**: Must be at the device to initiate
- **Preserves passwords**: Services continue working after reset

## Partition Layout

```
/dev/sda1 - [EFI]          - 512MB  - FAT32    - Normal boot
/dev/sda2 - [PROXMOX]      - Rest   - ZFS      - Main system
/dev/sda3 - [VAULT]        - 100MB  - LUKS     - Encrypted passwords
/dev/sda4 - [RECOVERY-OS]  - 500MB  - SQUASHFS - Immutable Alpine Linux
/dev/sda5 - [RECOVERY-IMG] - 10GB   - SQUASHFS - Compressed Proxmox image
/dev/sda6 - [RECOVERY-WRK] - 2GB    - EXT4     - Temp workspace
```

## Recovery Flow

### During Initial Install

1. Bootstrap checks for recovery partitions
2. If missing, creates partition structure
3. Generates unique passwords (SERVICES_PASSWORD, etc.)
4. Encrypts and stores passwords in VAULT partition
5. Creates golden Proxmox image before configuration
6. Installs Alpine-based recovery OS
7. Continues normal installation

### During Recovery

1. User selects "PrivateBox Recovery Mode" from GRUB menu
2. Alpine recovery OS boots (no password, auto-login)
3. User sees warning prompt:
   ```
   ========================================
   PRIVATEBOX FACTORY RECOVERY
   ========================================
   WARNING: This will completely erase and
   reinstall PrivateBox to factory defaults.

   Your unique passwords will be preserved.

   Do you wish to proceed? (type YES to confirm):
   ```
4. If confirmed:
   - Mounts encrypted vault (key embedded in recovery OS)
   - Retrieves stored passwords
   - Wipes main Proxmox partition
   - Restores golden Proxmox image
   - Configures network settings
   - Injects passwords into `/etc/privatebox/config.env`
   - Reboots to fresh system
5. Proxmox boots and runs bootstrap automatically with preserved passwords

## Security Implementation

### Vault Encryption

The VAULT partition uses LUKS encryption with a key embedded in the recovery OS:

```bash
# During setup
dd if=/dev/urandom of=/tmp/vault.key bs=512 count=1
cryptsetup luksFormat /dev/sda3 /tmp/vault.key

# Embed key in recovery initramfs
cp /tmp/vault.key /recovery/initramfs/etc/vault.key
shred -u /tmp/vault.key
```

### Why This Is "Good Enough"

- **Proxmox cannot decrypt vault** - Doesn't have the key
- **Recovery OS has key built-in** - No user interaction needed
- **Protects against remote attacks** - Primary threat for home users
- **Physical access assumed safe** - Home environment
- **Simple and reliable** - No complex key derivation

### Recovery OS Properties

- **No network services** - No SSH, no open ports
- **Console only** - Physical keyboard required
- **Immutable** - SquashFS filesystem, runs from RAM
- **Single purpose** - Only runs recovery script

## What Gets Preserved

### Preserved Across Recovery
- All generated passwords (SERVICES_PASSWORD, etc.)
- Installation UUID

### Reset to Defaults
- Network configuration (always 192.168.1.10/24)
- All VMs and containers
- All service configurations
- User data and customizations

## Implementation Notes

### Golden Image Creation

The Proxmox golden image is created during initial installation:
1. Minimal Proxmox installed
2. Before any configuration, system is snapshot
3. Image compressed and stored in RECOVERY-IMG partition
4. Normal bootstrap continues

### Recovery Workspace

The RECOVERY-WRK partition provides temporary space for:
- Decompressing the golden image
- Temporary mount points
- Log files during recovery

This partition is wiped after each recovery operation.

## User Experience

From the user's perspective:
1. System problem occurs
2. Reboot and select recovery from GRUB
3. Type "YES" to confirm
4. Wait ~10 minutes
5. System returns to factory state with same passwords
6. All services work immediately

This matches the experience of commercial home routers and NAS appliances - simple, predictable, and reliable.

## Future Enhancements

Potential improvements (not in initial implementation):
- Hardware button trigger via GPIO
- LED status indicators during recovery
- Backup user data to separate partition before reset
- Multiple recovery points (versioned golden images)

## Testing Recovery

To test the recovery system:
1. Make changes to the main system
2. Reboot and select recovery mode
3. Confirm the recovery
4. Verify system returns to original state
5. Verify passwords still work

Recovery can be tested as often as needed without wearing out flash storage (reads only, no writes to recovery partitions during normal operation).