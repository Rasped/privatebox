# PrivateBox Recovery System (v3 - ZFS Edition)

## Overview

PrivateBox includes a built-in recovery system that provides factory reset capability while preserving unique installation passwords. This creates a true appliance experience - users can always recover to a known-good state without losing their credentials.

This (v3) plan replaces LVM and LUKS with a ZFS-native layout. This provides the high-performance snapshots and data integrity features Proxmox is known for, while retaining the flexible, asset-preserving recovery model from the v2 plan.

## Design Goals

- **Simple**: One-button factory reset experience via boot menu
- **Secure**: Passwords encrypted and inaccessible from main OS
- **Offline**: No network required for recovery or re-provisioning
- **Physical-only**: Must be at the device to initiate
- **Preserves passwords**: Services continue working after reset
- **Fast Snapshots**: Leverages ZFS for instantaneous, low-impact system snapshots
- **Flexible**: ZFS datasets replace LVs for a more dynamic data structure

## Partition Layout

This design uses a ZFS-native layout. A single ZFS pool (rpool) manages all data, using datasets as "logical partitions."

### Physical Partition Layout

```
/dev/sda1 - [EFI]           - 512MB  - FAT32    - GRUB Bootloader
/dev/sda2 - [/boot]         - 1GB    - EXT4     - Unencrypted kernels (required to boot ZFS)
/dev/sda3 - [RECOVERY-OS]   - 1GB    - SQUASHFS - Immutable recovery environment
/dev/sda4 - [ZFS_RPOOL]     - Rest   - ZFS      - Main ZFS pool for all system data
```

### ZFS Dataset Layout

(Inside the /dev/sda4 ZFS Pool rpool)

```
rpool/
├── ROOT     - (Filesystem) - Main Proxmox OS (Wiped on reset)
│   └── data/
│       ├── vm-100-disk-0
│       └── vm-9000-disk-0
├── ASSETS   - (Filesystem) - Offline assets & installer files (Preserved)
├── VAULT    - (Filesystem) - Encrypted passwords (Preserved, Encrypted)
└── ... (Other ZFS datasets for VMs, containers, etc.)
```

(Note: ZFS datasets are dynamic and don't have fixed sizes, which is a major advantage.)

## Implementation Strategy

### ZFS-Native, Installer-Based Approach

The implementation leverages ZFS as the core storage technology, managed by a Debian Preseed installer.

**Phase 1: Offline Capability (Low Risk)**
- Download all assets (cloud images, container images, Debian installer files) to a staging area

**Phase 2: Installer, Recovery & Configuration**
- Create a Debian Preseed configuration (preseed.cfg)
- The preseed/late_command script is critical. It will be responsible for:
  - Installing ZFS packages (zfs-utils-linux)
  - Creating the rpool on /dev/sda4
  - Creating the ROOT, ASSETS, and VAULT datasets
- The Preseed process installs a minimal Debian, the Proxmox packages, and cloud-init directly into the rpool/ROOT dataset

### Key Technology Shift: "ZFS Datasets as Volumes"

This plan replaces LVM entirely. Instead of lv_proxmox, lv_assets, and lv_vault, we use ZFS datasets.

**Factory Reset Action:**
- LVM (v2): `mkfs.ext4 /dev/vg_privatebox/lv_proxmox` (Slow)
- ZFS (v3): `zfs destroy -r rpool/ROOT && zfs create rpool/ROOT` (Instant)

This is dramatically faster and cleaner. The recovery script simply destroys the main OS dataset and creates a new empty one, leaving rpool/ASSETS and rpool/VAULT completely untouched.

### Configuration Management: cloud-init

This remains identical to the v2 plan. cloud-init runs on first boot, reads its configuration from rpool/ASSETS, and provisions the appliance.

## Security Implementation

### ZFS Native Encryption

This plan replaces LUKS with ZFS native encryption, which is simpler and more flexible. We only encrypt the VAULT dataset.

**Vault Creation (During Initial Install):**

1. A raw encryption key is generated:
   ```bash
   dd if=/dev/urandom of=/tmp/vault.key bs=32 count=1
   ```

2. The VAULT dataset is created with this key:
   ```bash
   zfs create -o encryption=on -o keylocation=file:///tmp/vault.key -o keyformat=raw rpool/VAULT
   ```

3. The vault.key file is then stored in two secure locations:
   - In the initramfs of the [RECOVERY-OS] on sda3
   - In a secure location within rpool/ASSETS (e.g., in the cloud-init config), for the main OS to use

**Security Properties:**
- **Proxmox cannot access vault (by default)**: The rpool/VAULT dataset is not auto-mounted. It is only mounted by the cloud-init script, which knows where to find the key and how to load it
- **Recovery OS has key**: The recovery environment's initramfs contains the key, allowing it to mount rpool/VAULT if needed (e.g., to verify credentials)

## Recovery Flow

### During Initial Install (Booting from temporary USB)

1. A technician boots the appliance from a custom Debian Installer USB
2. The Preseed installer auto-partitions sda1, sda2, and sda3
3. Preseed late_command script runs:
   - Installs ZFS packages
   - Creates the ZFS rpool on sda4
   - Creates datasets: `zfs create rpool/ROOT`, `zfs create rpool/ASSETS`
   - Generates vault.key and creates encrypted dataset: `zfs create -o encryption=on ... rpool/VAULT`
   - Installs the OS (Debian + Proxmox + cloud-init) into rpool/ROOT
   - Installs the [RECOVERY-OS] onto sda3 and injects the vault.key into its initramfs
   - Mounts rpool/ASSETS and populates it with all offline assets (installer files, cloud-init configs, vault.key)
   - Mounts rpool/VAULT (using the key) and populates it with the generated passwords
4. Preseed Configures Bootloader: GRUB is installed on sda1, configured to boot from sda2 (/boot) and rpool/ROOT (/). It includes the "PrivateBox Factory Reset" entry
5. The appliance reboots. The cloud-init process runs for the first time

### During a Factory Reset (User-initiated)

1. User selects "PrivateBox Factory Reset" from the GRUB menu
2. The immutable [RECOVERY-OS] from sda3 boots
3. User sees the warning prompt and types "YES"
4. The recovery script executes:
   - Imports the ZFS rpool
   - Executes ZFS reset:
     ```bash
     zfs destroy -r rpool/ROOT
     zfs create rpool/ROOT
     ```
   - Mounts rpool/ASSETS
   - Executes kexec to load the Debian installer kernel (vmlinuz) and initrd (initrd.gz) from rpool/ASSETS
5. **Unattended Re-install**: The Debian Installer starts from RAM
   - It loads the recovery_preseed.cfg from rpool/ASSETS
   - The preseed file's "partitioning" recipe is now very simple: it's configured to find the existing rpool/ROOT and sda2 and use them as / and /boot
   - It installs a fresh, virgin Debian + Proxmox + cloud-init onto rpool/ROOT
6. **System Reboots**: The installer finishes and reboots
7. **First Boot (cloud-init)**:
   - The fresh Proxmox system boots
   - cloud-init starts automatically
   - It finds its user-data config on rpool/ASSETS
   - It finds the vault.key on rpool/ASSETS, uses it to load the rpool/VAULT encryption, and mounts the vault
   - It reads the preserved passwords and provisions the entire appliance from the offline assets

## What Gets Preserved

### Preserved Across Recovery
- **ZFS Datasets**: rpool/ASSETS and rpool/VAULT are never touched by the reset
- **Physical Partitions**: sda1, sda2, sda3, and sda4 (the pool) are untouched

### Reset to Defaults
- **ZFS Dataset**: rpool/ROOT is completely destroyed and recreated (recursive)
- All VMs and containers (which live on datasets under rpool/ROOT)
- All service configurations and user data

## Implementation Notes

### ZFS on Debian Preseed

The most complex part of this plan is the preseed/late_command script for the initial install. It must reliably install ZFS into the installer environment and bootstrap the pool before the OS is installed. This is a common procedure for "ZFS on Root" Debian installations and is well-documented.

The recovery script (sda3) is now dramatically simpler, as it only needs to run `zfs destroy`.

### Dataset Hierarchy

Understanding the dataset hierarchy is critical:

```
rpool/
├── ROOT/              ← Destroyed recursively on reset
│   ├── data/         ← All VM disks live here
│   │   ├── vm-100-disk-0
│   │   └── vm-9000-disk-0
│   └── ... (all Proxmox system data)
├── ASSETS/            ← Preserved (sibling, not child of ROOT)
└── VAULT/             ← Preserved (sibling, not child of ROOT)
```

The `-r` flag on `zfs destroy -r rpool/ROOT` destroys ROOT and all nested datasets. ASSETS and VAULT survive because they are siblings, not children.

## Asset Management for Offline Operation

Identical to the v2 plan, but the asset path is now a ZFS mountpoint.

### Assets Dataset Structure (Logical)

```
/rpool/ASSETS/
├── installer/
│   ├── vmlinuz
│   ├── initrd.gz
│   ├── preseed.cfg
│   ├── cloud-init/
│   │   ├── user-data
│   │   ├── meta-data
│   │   └── vault.key
├── images/
│   ├── debian-13-cloudimg-amd64.qcow2
│   └── ...
├── containers/
│   ├── adguard-home-latest.tar
│   ├── homer-latest.tar
│   ├── portainer-ce-latest.tar
│   ├── semaphore-latest.tar
│   └── manifest.json
├── templates/
│   └── opnsense-template.tar.gz
└── source/
    └── privatebox-main.tar.gz
```

### Script Modifications

All provisioning scripts (now part of the cloud-init user-data) must be modified to check these local paths first:

- **Debian Cloud Image**: Check `/rpool/ASSETS/images/debian-13...`
- **Container Images**: Check `/rpool/ASSETS/containers/<service>.tar` and use `podman load`
- **OPNsense Template**: Check `/rpool/ASSETS/templates/opnsense...`

## User Experience

From the user's perspective:
1. System problem occurs
2. Reboot and select recovery from GRUB
3. Type "YES" to confirm
4. Wait ~10-15 minutes (for a full re-install and cloud-init run)
5. System returns to factory state with the same passwords
6. All services work immediately

This matches the experience of commercial home routers and NAS appliances - simple, predictable, and reliable.

## Integration with Update Architecture

This recovery system complements the update architecture (see `documentation/update-architecture.md`):

**For Updates:** ZFS snapshots of rpool/ROOT before changes (instant, reversible)
```bash
zfs snapshot rpool/ROOT@pre-update-20251023
# If update fails:
zfs rollback rpool/ROOT@pre-update-20251023
```

**For Recovery:** ZFS destroy rpool/ROOT and reinstall (nuclear option)
```bash
zfs destroy -r rpool/ROOT
zfs create rpool/ROOT
# Then: reinstall via recovery
```

Both strategies use the same ZFS foundation and preserve rpool/ASSETS and rpool/VAULT.

## Future Enhancements

Potential improvements (not in initial implementation):
- Hardware button trigger via GPIO
- LED status indicators during recovery
- Backup user data to separate partition before reset
- Multiple recovery points (versioned golden images)
- ZFS send/receive for external backups

## Testing Recovery

To test the recovery system:
1. Make changes to the main system
2. Reboot and select recovery mode
3. Confirm the recovery
4. Verify system returns to original state
5. Verify passwords still work

Recovery can be tested as often as needed. ZFS snapshots can be used to speed up testing (snapshot before test, rollback after).
