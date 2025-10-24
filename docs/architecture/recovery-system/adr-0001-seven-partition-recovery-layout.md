---
status: accepted
date: 2025-10-24
deciders:
  - Rasped
superseded_by: null
---

# ADR-0001: Seven-Partition Recovery Layout with ZFS

## Context

PrivateBox is a commercial consumer appliance requiring factory reset capability without vendor support. Key requirements:

**Business context:**
- Consumers expect appliance-like "reset to factory defaults" functionality
- No phone support model - reset must work offline without assistance
- EU 2-year warranty requires reliable recovery mechanisms
- Competing products (Firewalla, Ubiquiti) offer similar recovery features

**Technical constraints:**
- Intel N150 hardware with 256GB SSD
- Must preserve unique installation passwords across resets (no shared defaults)
- Proxmox VE as hypervisor platform (Debian-based, ZFS-native)
- Physical console access guaranteed (VGA/HDMI + USB keyboard)

**Security requirements:**
- Passwords must be inaccessible from main OS (protect against root compromise)
- Recovery must require physical access (no remote factory reset attacks)
- Offline operation (broken network shouldn't prevent recovery)

**Timeline pressure:**
- Late 2025 product launch
- Need proven, stable technologies (no experimental features)

## Decision

We will implement a **7-partition layout using ZFS** for the recovery system:

### Physical Partitions
1. `/dev/sda1` - EFI boot (512MB, FAT32)
2. `/dev/sda2` - /boot (1GB, ext4, unencrypted kernels)
3. `/dev/sda3` - Recovery OS (1GB, SquashFS, immutable)
4. `/dev/sda4` - ZFS pool (remaining space)

### ZFS Datasets (within sda4 pool)
5. `rpool/ROOT` - Main Proxmox OS (destroyed on reset)
6. `rpool/ASSETS` - Offline installer assets (preserved)
   - `factory/` slot - immutable original assets
   - `updated/` slot - atomically updated assets
7. `rpool/VAULT` - Encrypted password storage (preserved, ZFS native encryption)

### Key Design Elements

**Two-Slot Asset Architecture:**
- `factory/`: Populated during PXE provisioning, made read-only, never modified
- `updated/`: Initially empty, atomically replaced on updates
- Recovery menu offers: "Latest Version" (updated→factory fallback) or "Original Shipped" (factory only)

**Security Model:**
- Vault encryption key stored ONLY in Recovery OS initramfs on sda3
- Main Proxmox OS cannot decrypt or access vault
- Passwords injected into cloud-init config only during recovery process

**Recovery Process:**
1. User selects recovery from GRUB menu (physical access required)
2. Immutable Recovery OS boots from sda3
3. User confirms with "YES" prompt
4. Recovery script: `zfs destroy -r rpool/ROOT && zfs create rpool/ROOT`
5. Mounts vault, reads passwords, injects into selected asset slot
6. Uses kexec to load Debian installer from assets
7. Installer reinstalls Proxmox to fresh rpool/ROOT
8. cloud-init provisions services using offline assets + preserved passwords

## Consequences

### Positive

**For customers:**
- True appliance experience - one-button factory reset
- No dependency on vendor (offline, self-contained)
- Passwords preserved - services work immediately after reset
- Permanent failsafe - can always restore to shipped state

**For business:**
- Reduces support burden (customers self-recover)
- Competitive feature parity with Firewalla/Ubiquiti
- Enables confident software updates (can always roll back)
- EU warranty compliance (reliable recovery mechanism)

**Technical benefits:**
- ZFS instant snapshots for updates (`zfs snapshot rpool/ROOT@pre-update`)
- Instant factory reset (`zfs destroy` is milliseconds, not minutes)
- Atomic asset updates (destroy + create dataset)
- Data integrity (ZFS checksums prevent silent corruption)
- Flexible storage (datasets grow/shrink dynamically)

### Negative

**Complexity:**
- ZFS setup in Debian Preseed is non-trivial
- Custom Recovery OS build process required (debootstrap + SquashFS)
- Must manage ZFS version compatibility between Recovery OS and Proxmox
- More moving parts than simple partition imaging

**Storage overhead:**
- 3GB for EFI/boot/recovery partitions (fixed)
- Dual asset slots (factory + updated) ~4GB total
- Encrypted vault ~10MB
- Total overhead: ~7GB on 256GB SSD (~3% overhead - acceptable)

**Update complexity:**
- Asset updates must be atomic (destroy + create + populate)
- Must validate checksums before replacing updated slot
- Recovery OS updates require rebuilding SquashFS (rare)

**Testing burden:**
- Recovery process must be tested thoroughly
- PXE provisioning server required for production
- Need to test both "latest" and "factory" recovery paths

### Neutral

**ZFS commitment:**
- Now tied to ZFS ecosystem (Proxmox already uses ZFS, so not a new dependency)
- Can't easily switch to LVM/ext4 later without full redesign

**Factory provisioning infrastructure:**
- Requires PXE server infrastructure in production
- Initial setup cost, but necessary for commercial production anyway

**Partition layout is permanent:**
- 7-partition structure set at first install, can't be changed without full wipe
- Asset slot architecture can't easily be expanded (factory + updated only)

## Alternatives Considered

### Alternative 1: Simple Partition Imaging (rsync to backup partition)
**Approach:** Reserve partition for rsync'd system backup, restore by copying back

**Pros:**
- Simple, well-understood
- No custom recovery OS needed

**Cons:**
- Slow restore (copy entire filesystem)
- No password preservation (would need separate vault anyway)
- Wastes space (duplicate system partition)
- No atomic updates
- **Rejected because:** Too slow for consumer appliance expectations, no advantage over ZFS

### Alternative 2: LVM with Logical Volumes
**Approach:** Use LVM instead of ZFS datasets

**Pros:**
- More familiar to some admins
- Slightly less complex than ZFS

**Cons:**
- No instant snapshots (LVM snapshots degrade performance)
- Factory reset requires `mkfs` (slow)
- No data integrity checksums
- No native encryption (would still need LUKS)
- **Rejected because:** Proxmox already uses ZFS, LVM adds no value

### Alternative 3: External USB Recovery Media
**Approach:** Ship USB stick with recovery image, user boots from USB to recover

**Pros:**
- No recovery partition needed (saves ~1GB)
- Easy to update recovery media (ship new USB)

**Cons:**
- Users lose USB sticks (support nightmare)
- Requires USB port to be accessible (not always true for rack-mount)
- Can't guarantee offline operation (USB could be lost during network outage)
- **Rejected because:** Poor customer experience, support burden too high

### Alternative 4: Cloud-Based Recovery
**Approach:** Download recovery image from vendor servers

**Pros:**
- Always latest recovery version
- No local storage overhead

**Cons:**
- Requires working network (defeats purpose if network is broken)
- Vendor dependency (against "no cloud" selling point)
- Privacy concerns (device phones home)
- Fails if vendor goes out of business
- **Rejected because:** Violates core product philosophy (offline-first, no vendor lock-in)

## Implementation Notes

**Key files affected:**
- `bootstrap/preseed.cfg` - Debian installer automation
- `ansible/playbooks/recovery/build-recovery-os.yml` - Recovery OS build
- `ansible/files/recovery/recovery-script.sh` - Recovery execution script
- `documentation/recovery/recovery-system.md` - User-facing documentation

**Migration path:**
- Fresh installs only - existing systems would need manual migration (not planned)

**Testing approach:**
- Test PXE provisioning on physical Intel N150 hardware
- Automated tests for asset validation and checksums
- Manual recovery tests on representative hardware
- Test both recovery paths (latest and factory)

**Rollback strategy:**
- If major issues found, can revert to simple Proxmox install without recovery (v0.9.x approach)
- No rollback possible after customer shipment (partition layout is permanent)

## References

- [Recovery System Overview](./overview.md) - Full implementation details
- ZFS on Debian: https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/
- Proxmox ZFS: https://pve.proxmox.com/wiki/ZFS_on_Linux
- Debian Preseed: https://wiki.debian.org/DebianInstaller/Preseed
- Related: [ADR-0003: ZFS Native Encryption Over LUKS](./adr-0003-zfs-over-luks.md) *(to be created)*
