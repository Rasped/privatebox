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

3. The vault.key file is stored in ONE secure location:
   - In the initramfs of the [RECOVERY-OS] on sda3 (embedded in read-only image)
   - **NOT stored on rpool/ASSETS** - Main OS cannot access the key

**Security Properties:**
- **Proxmox CANNOT access vault**: The main OS has no way to decrypt or mount rpool/VAULT. The key exists only in the recovery OS initramfs on sda3
- **Recovery OS has exclusive key access**: Only the recovery environment can mount rpool/VAULT
- **Password injection happens during reset only**: The recovery script mounts the vault, reads passwords, and injects them into the cloud-init config on rpool/ASSETS just before triggering the reinstall
- **Protects against root compromise**: Even if an attacker gains root on Proxmox, they cannot access the vault or steal the permanent passwords

## Factory Provisioning Setup

**Production Method:** All appliances are provisioned via PXE boot from a factory provisioning server. USB installation is only used for development and testing.

### Provisioning Server Requirements

The factory provisioning server must provide:

1. **DHCP Server**: Assigns IP addresses and provides PXE boot information
2. **TFTP Server**: Serves the network boot loader and kernel/initrd
3. **HTTP Server**: Hosts preseed configuration and offline assets
4. **Asset Repository**: Stores all required assets (container images, VM templates, installer files)

### Provisioning Server Directory Structure

```
/srv/privatebox-provisioning/
├── tftp/
│   ├── pxelinux.0           # PXE boot loader
│   ├── ldlinux.c32          # Required by pxelinux
│   ├── pxelinux.cfg/
│   │   └── default          # PXE menu configuration
│   ├── debian-installer/
│   │   ├── amd64/
│   │   │   ├── linux        # Debian installer kernel
│   │   │   └── initrd.gz    # Debian installer initrd
├── http/
│   ├── preseed.cfg          # Automated installation configuration
│   └── assets/              # All offline assets
│       ├── images/
│       │   └── debian-13-cloudimg-amd64.qcow2
│       ├── containers/
│       │   ├── adguard-home-latest.tar
│       │   ├── portainer-ce-latest.tar
│       │   ├── semaphore-latest.tar
│       │   └── homer-latest.tar
│       ├── templates/
│       │   └── opnsense-template.tar.gz
│       ├── installer/
│       │   ├── vmlinuz
│       │   ├── initrd.gz
│       │   ├── preseed.cfg
│       │   └── cloud-init/
│       │       ├── user-data
│       │       └── meta-data
│       └── recovery/
│           └── recovery.squashfs  # Pre-built recovery OS
```

### PXE Boot Configuration

```
# /srv/privatebox-provisioning/tftp/pxelinux.cfg/default
DEFAULT install
LABEL install
  KERNEL debian-installer/amd64/linux
  APPEND initrd=debian-installer/amd64/initrd.gz auto=true priority=critical url=http://provisioning-server/preseed.cfg
```

### Preseed Configuration (Key Sections)

The preseed.cfg on the provisioning server includes special commands to download assets:

```bash
# In preseed/late_command:
d-i preseed/late_command string \
    in-target wget -r -np -nH --cut-dirs=2 \
    http://provisioning-server/assets/ \
    -P /rpool/ASSETS/
```

## Recovery Flow

### During Initial Install (PXE Boot from Factory)

1. **Appliance powers on**, network boots via PXE
2. **DHCP assigns IP** and directs to TFTP server
3. **PXE boot loader** downloads Debian installer kernel and initrd from TFTP
4. **Installer boots** and automatically loads preseed.cfg from HTTP server
5. **Preseed installer** runs non-interactively:
   - Auto-partitions sda1 (EFI), sda2 (/boot), sda3 (RECOVERY-OS), sda4 (ZFS pool)
6. **Preseed late_command script** runs:
   - Installs ZFS packages
   - Creates the ZFS rpool on sda4
   - Creates datasets: `zfs create rpool/ROOT`, `zfs create rpool/ASSETS`
   - **Downloads all offline assets** from provisioning server to rpool/ASSETS:
     ```bash
     wget -r -np -nH --cut-dirs=2 http://provisioning-server/assets/ -P /rpool/ASSETS/
     ```
   - Downloads pre-built recovery OS: `wget http://provisioning-server/assets/recovery/recovery.squashfs -O /tmp/recovery.squashfs`
   - Generates vault.key and creates encrypted dataset: `zfs create -o encryption=on ... rpool/VAULT`
   - Installs the [RECOVERY-OS] onto sda3:
     ```bash
     dd if=/tmp/recovery.squashfs of=/dev/sda3 bs=1M
     ```
   - Injects the vault.key into the recovery OS SquashFS metadata (or rebuilds with key embedded)
   - Installs the OS (Debian + Proxmox + cloud-init) into rpool/ROOT
   - Generates unique passwords (SERVICES_PASSWORD, etc.)
   - Mounts rpool/VAULT (using the key) and populates it with the generated passwords
   - Deletes vault.key from disk (only exists in recovery OS and for initial cloud-init)
7. **Preseed Configures Bootloader**: GRUB is installed on sda1, configured to boot from sda2 (/boot) and rpool/ROOT (/). It includes the "PrivateBox Factory Reset" entry
8. **Appliance reboots from local disk**. The cloud-init process runs for the first time, provisioning all VMs and services using assets from rpool/ASSETS

**Total provisioning time:** 20-30 minutes (depending on network speed for asset download)

**Development/Testing Alternative:** For development, a bootable USB can be created with preseed.cfg and assets bundled. The flow is identical except assets are copied from USB instead of downloaded via HTTP.

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
   - Mounts rpool/VAULT using the vault.key from its own initramfs
   - Reads the preserved passwords from rpool/VAULT
   - Mounts rpool/ASSETS
   - Injects the passwords into the cloud-init user-data config on rpool/ASSETS
   - Unmounts rpool/VAULT (vault is now inaccessible until next reset)
   - Executes kexec to load the Debian installer kernel (vmlinuz) and initrd (initrd.gz) from rpool/ASSETS
5. **Unattended Re-install**: The Debian Installer starts from RAM
   - It loads the recovery_preseed.cfg from rpool/ASSETS
   - The preseed file's "partitioning" recipe is now very simple: it's configured to find the existing rpool/ROOT and sda2 and use them as / and /boot
   - It installs a fresh, virgin Debian + Proxmox + cloud-init onto rpool/ROOT
6. **System Reboots**: The installer finishes and reboots
7. **First Boot (cloud-init)**:
   - The fresh Proxmox system boots
   - cloud-init starts automatically
   - It finds its user-data config on rpool/ASSETS (with passwords already injected by recovery script)
   - It provisions the entire appliance from the offline assets using the preserved passwords

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

### Building the Recovery OS

The recovery OS on sda3 must be a custom minimal Debian environment, not Alpine Linux or a full-featured rescue distribution.

**Why Custom Debian (Not Alpine or Finnix):**

1. **Tooling Compatibility (Critical):** The recovery script must manipulate the Proxmox ZFS pool using `zfs-utils-linux`. Proxmox is built on Debian (glibc-based). Alpine Linux uses musl libc instead of glibc, which can cause subtle incompatibilities with ZFS tools. Using the same Debian base guarantees binary compatibility.

2. **Minimal Size:** We need ~100-200MB, not 500MB+. Finnix and other full rescue distributions are overkill. We need exactly: kernel, BusyBox, zfs-utils-linux, and the recovery script. Nothing else.

3. **Immutable Security:** A read-only SquashFS image cannot be modified by the main OS or by an attacker. This is perfect for a security-critical recovery tool.

**Build Process Using debootstrap:**

```bash
# 1. Create minimal Debian rootfs
RECOVERY_ROOT="/tmp/recovery-build"
mkdir -p "$RECOVERY_ROOT"

debootstrap --variant=minbase --include=busybox,zfsutils-linux \
    trixie "$RECOVERY_ROOT" http://deb.debian.org/debian/

# 2. Configure the recovery environment
cat > "$RECOVERY_ROOT/etc/fstab" <<EOF
# Recovery OS runs entirely from RAM
tmpfs  /tmp  tmpfs  defaults  0 0
EOF

# 3. Install the recovery script
cat > "$RECOVERY_ROOT/usr/local/bin/privatebox-recovery" <<'EOF'
#!/bin/bash
# The actual recovery script (shown in "During a Factory Reset" section)
set -e

# Display warning prompt
echo "========================================"
echo "PRIVATEBOX FACTORY RECOVERY"
echo "========================================"
echo "WARNING: This will completely erase and"
echo "reinstall PrivateBox to factory defaults."
echo ""
echo "Your unique passwords will be preserved."
echo ""
read -p "Do you wish to proceed? (type YES to confirm): " confirm

[[ "$confirm" != "YES" ]] && { echo "Aborted."; exit 1; }

# Import ZFS pool
zpool import -f rpool

# Destroy and recreate ROOT
zfs destroy -r rpool/ROOT
zfs create rpool/ROOT

# Mount VAULT using embedded key
zfs load-key -L file:///etc/vault.key rpool/VAULT
zfs mount rpool/VAULT

# Read passwords from vault
SERVICES_PASSWORD=$(cat /rpool/VAULT/services_password)

# Mount ASSETS
zfs mount rpool/ASSETS

# Inject passwords into cloud-init config
sed -i "s/__SERVICES_PASSWORD__/$SERVICES_PASSWORD/" /rpool/ASSETS/installer/cloud-init/user-data

# Unmount vault (inaccessible until next reset)
zfs unmount rpool/VAULT

# Load installer kernel and initrd from ASSETS
kexec -l /rpool/ASSETS/installer/vmlinuz \
    --initrd=/rpool/ASSETS/installer/initrd.gz \
    --append="auto=true priority=critical url=file:///rpool/ASSETS/installer/preseed.cfg"

# Execute installer
kexec -e
EOF

chmod +x "$RECOVERY_ROOT/usr/local/bin/privatebox-recovery"

# 4. Create auto-login and auto-run recovery script
cat > "$RECOVERY_ROOT/etc/inittab" <<EOF
# Auto-login to root and run recovery script
::sysinit:/etc/init.d/rcS
::respawn:/usr/local/bin/privatebox-recovery
::ctrlaltdel:/sbin/reboot
EOF

# 5. Embed vault.key in the recovery initramfs
mkdir -p "$RECOVERY_ROOT/etc"
cp /path/to/vault.key "$RECOVERY_ROOT/etc/vault.key"
chmod 400 "$RECOVERY_ROOT/etc/vault.key"

# 6. Create SquashFS image
mksquashfs "$RECOVERY_ROOT" /tmp/recovery.squashfs -comp xz -b 1M

# 7. Copy to sda3 partition
dd if=/tmp/recovery.squashfs of=/dev/sda3 bs=1M

# 8. Configure GRUB to boot recovery OS
cat >> /etc/grub.d/40_custom <<EOF
menuentry 'PrivateBox Factory Reset' {
    insmod ext2
    insmod squashfs
    set root='hd0,gpt3'
    linux /vmlinuz boot=live live-media=/dev/sda3
    initrd /initrd.img
}
EOF

update-grub
```

**Key Implementation Details:**

1. **debootstrap --variant=minbase:** Creates the smallest possible Debian base (no documentation, no recommended packages)

2. **BusyBox:** Provides minimal shell and core utilities (~2MB instead of hundreds of MB for bash + coreutils)

3. **zfsutils-linux:** The critical package - must be the same version as on Proxmox host

4. **Auto-boot behavior:** The recovery OS automatically logs in as root and immediately runs the recovery script. No user interaction except the "YES" confirmation.

5. **Vault key embedding:** The vault.key is copied into /etc/vault.key inside the recovery root filesystem BEFORE creating the SquashFS. Once the SquashFS is created, the key is embedded and immutable.

6. **kexec usage:** The recovery OS uses kexec to load the Debian installer directly from rpool/ASSETS without rebooting. This preserves the ZFS pool state and injected passwords.

**Size Estimate:**
- Debian minbase: ~40MB
- BusyBox: ~2MB
- zfsutils-linux: ~20MB
- Kernel + initrd: ~50MB
- Recovery script: <1MB
- **Total: ~120MB** (well under 1GB sda3 partition)

**Testing the Recovery OS:**

Before deploying to sda3, test the recovery environment:

```bash
# Mount the SquashFS and chroot into it
mkdir /tmp/test-recovery
mount -t squashfs /tmp/recovery.squashfs /tmp/test-recovery
chroot /tmp/test-recovery /bin/sh

# Verify tools are available
which zfs
which zpool
zfs --version  # Should match Proxmox version

# Verify recovery script exists
/usr/local/bin/privatebox-recovery --help  # (or dry-run mode)
```

## Asset Management for Offline Operation

Identical to the v2 plan, but the asset path is now a ZFS mountpoint.

### Assets Dataset Structure (Logical)

```
/rpool/ASSETS/
├── installer/
│   ├── vmlinuz
│   ├── initrd.gz
│   ├── preseed.cfg
│   └── cloud-init/
│       ├── user-data          (passwords injected by recovery script)
│       └── meta-data
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

**Note:** The vault.key does NOT exist in rpool/ASSETS. It exists only in the recovery OS initramfs on sda3.

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
