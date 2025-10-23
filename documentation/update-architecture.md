# PrivateBox Update Architecture

## Overview

PrivateBox provides safe, rollback-capable updates for all system components using ZFS snapshots. This creates a professional appliance experience where users can confidently apply updates without fear of breaking their system.

## Design Goals

- **Safe**: Always have a rollback point before updates
- **Automated**: Snapshot creation and health checks built into update process
- **Fast**: ZFS snapshots are instant (copy-on-write)
- **Granular**: Can update and rollback individual components
- **User-friendly**: One-button updates via Semaphore UI
- **Efficient**: Minimal disk overhead compared to full backups

## Philosophy: Defense in Depth

PrivateBox uses a layered update safety strategy:

| Layer | Protection | Use Case |
|-------|------------|----------|
| **ZFS Snapshots** | Point-in-time rollback | Update broke something, rollback immediately |
| **Configuration Backups** | Config-only restore | Want to try fresh install but keep settings |
| **Factory Reset** | Nuclear option | System completely broken, start over |

Each layer serves a different recovery scenario.

## What Gets Updated

### 1. Proxmox Host (Rare)
- **Frequency**: Monthly security updates, major version updates annually
- **Risk**: HIGH (kernel/ZFS breakage = no boot, highest impact)
- **Strategy**: Manual snapshot of rpool/ROOT before updates
- **Rollback**: Boot from recovery USB, import pool, ZFS rollback (or factory reset if pool corrupted)

### 2. OPNsense VM (Regular)
- **Frequency**: Weekly/monthly firmware updates
- **Risk**: HIGH (network failure = total loss of connectivity)
- **Strategy**: Automatic ZFS snapshot + health check
- **Rollback**: Instant via ZFS snapshot

### 3. Management VM Services (Frequent)
- **Frequency**: Container image updates as needed
- **Risk**: Medium (services fail but network still works)
- **Strategy**: Per-service snapshots or full VM snapshot
- **Rollback**: Instant via ZFS snapshot

### 4. Individual Containers (Frequent)
- **Frequency**: Ad-hoc (AdGuard, Portainer, etc.)
- **Risk**: Low (only affects that service)
- **Strategy**: VM-level snapshot covers all containers
- **Rollback**: Instant via ZFS snapshot

## ZFS Snapshot Strategy

### Why ZFS?

**Technical Benefits:**
- Copy-on-write: Snapshots are instant, zero downtime
- Space-efficient: Only changed blocks consume space
- Reliable: Atomic operations, no partial states
- Fast rollback: Revert to snapshot in seconds

**Versus Alternatives:**
- LVM snapshots: Slower, pre-allocated space, require reboot for rollback
- vzdump backups: Full copy, slow, large storage overhead
- VM clones: Fast but consume 2x disk space

**Requirements:**
- Proxmox installed with ZFS storage backend
- Sufficient RAM (1GB per TB recommended, 16GB total for 256GB SSD is excellent)
- Single disk RAID0 acceptable (factory reset provides disaster recovery)

### Snapshot Naming Convention

```
rpool/data/vm-{VMID}-disk-0@{type}-{timestamp}-{description}

Examples:
rpool/data/vm-100-disk-0@pre-update-20251023-opnsense-24.7.6
rpool/data/vm-9000-disk-0@pre-update-20251023-management-vm
rpool/data/vm-100-disk-0@daily-20251023-0300
rpool/data/vm-100-disk-0@manual-20251023-before-config-change
```

**Snapshot Types:**
- `pre-update`: Automatic snapshot before applying updates
- `daily`: Automated daily snapshots (retention: 7 days)
- `weekly`: Automated weekly snapshots (retention: 4 weeks)
- `manual`: User-initiated snapshots via Semaphore
- `pre-host-update`: Manual snapshot before Proxmox host updates

### Snapshot Retention Policy

| Type | Retention | Purpose |
|------|-----------|---------|
| `pre-update` | 14 days | Rollback recent VM updates |
| `daily` | 7 days | Recover from recent mistakes |
| `weekly` | 4 weeks | Longer-term recovery point |
| `manual` | Until deleted | User-controlled checkpoints |
| `pre-host-update` | 30 days | Rollback catastrophic host updates |

Automated cleanup runs daily, removing expired snapshots.

**Note:** The "golden" deployment state lives in rpool/ASSETS (offline installer files and cloud-init configs), not as a ZFS snapshot. Factory reset uses these assets to provision a fresh system.

## Safe Update Flow

### Proxmox Host Update Example

**User Action:** SSH to Proxmox host, manually update

**Manual Steps:**
1. **Create snapshot of entire root**
   ```bash
   zfs snapshot -r rpool/ROOT@pre-host-update-$(date +%Y%m%d)
   ```
   The `-r` flag creates recursive snapshots of all datasets under rpool/ROOT

2. **Apply updates**
   ```bash
   apt update && apt upgrade -y
   ```

3. **Reboot and test**
   ```bash
   reboot
   ```
   - System should boot normally
   - All VMs should be accessible
   - Proxmox web UI should load

4. **If boot fails:**
   - Boot from Debian live USB
   - Import the pool: `zpool import -f rpool`
   - Rollback: `zfs rollback -r rpool/ROOT@pre-host-update-YYYYMMDD`
   - Reboot to restored system

5. **If boot succeeds:**
   - Keep snapshot for 30 days
   - Manual cleanup: `zfs destroy -r rpool/ROOT@pre-host-update-YYYYMMDD`

**Total time:** 10-20 minutes (depends on update size)

**Note:** Host updates cannot be automated safely due to reboot requirement and potential for catastrophic failure. Manual snapshot + testing is the safest approach.

### OPNsense Update Example

**User Action:** Click "Update OPNsense (Safe)" in Semaphore

**Automated Steps:**
1. **Pre-flight checks**
   - Verify ZFS available: `zfs list rpool/data/vm-100-disk-0`
   - Check free space (need ~10% free for snapshots)
   - Verify OPNsense reachable (ping, web UI check)

2. **Create snapshot**
   ```bash
   zfs snapshot rpool/data/vm-100-disk-0@pre-update-$(date +%Y%m%d-%H%M)-opnsense
   ```

3. **Apply update**
   - SSH to OPNsense or use API
   - Trigger firmware update
   - Wait for completion

4. **Health checks** (automatic post-update validation)
   - Wait 30 seconds for services to stabilize
   - Ping test: `ping -c 3 10.10.20.1`
   - Web UI test: `curl -sSk https://10.10.20.1` (expect HTTP 200)
   - DNS test: `dig @10.10.20.1 google.com` (Unbound working)
   - Gateway test: From management VM, `ping 8.8.8.8` (routing works)

5. **Result handling**
   - **If all checks pass:** Success, keep snapshot for 14 days
   - **If any check fails:** Auto-rollback + alert user

**Total time:** 5-10 minutes (most of it waiting for OPNsense update)

### Management VM Update Example

Similar flow but health checks are different:
- Portainer API responding
- Semaphore API responding
- AdGuard DNS responding
- Caddy reverse proxy working

### Rollback Flow

**Automatic Rollback (health check failed):**
```bash
# Stop VM
qm stop 100

# Rollback to snapshot
zfs rollback rpool/data/vm-100-disk-0@pre-update-20251023-1430-opnsense

# Start VM
qm start 100

# Wait and verify
sleep 30
ping -c 3 10.10.20.1 || error "Rollback failed - manual intervention needed"
```

**Manual Rollback (user notices issue later):**
User clicks "Rollback OPNsense" in Semaphore, selects snapshot from list, confirms.

**Rollback time:** ~60 seconds (VM stop + snapshot rollback + VM start)

## ZFS Requirement Check

Bootstrap must verify ZFS before proceeding with PrivateBox installation.

### Detection Script

```bash
# Check if Proxmox is using ZFS
check_zfs() {
    log "Checking for ZFS storage..."

    # Method 1: Check for ZFS pools
    if ! command -v zfs &>/dev/null; then
        error_exit "ZFS tools not found. PrivateBox requires Proxmox installed with ZFS storage."
    fi

    # Method 2: Check for rpool
    if ! zpool list rpool &>/dev/null 2>&1; then
        error_exit "ZFS pool 'rpool' not found. PrivateBox requires ZFS storage backend."
    fi

    # Method 3: Verify VM storage is ZFS
    local storage_type=$(pvesm status | grep "^local-zfs" | awk '{print $2}')
    if [[ "$storage_type" != "zfspool" ]]; then
        error_exit "Storage 'local-zfs' not found or not ZFS type. Found: $storage_type"
    fi

    # Check available space
    local avail=$(zfs list -Hp -o available rpool/data 2>/dev/null | head -1)
    local avail_gb=$((avail / 1024 / 1024 / 1024))

    if [[ $avail_gb -lt 50 ]]; then
        error_exit "Insufficient space on rpool/data: ${avail_gb}GB available (50GB minimum required)"
    fi

    display "  ✓ ZFS storage verified (${avail_gb}GB available)"
}
```

### Where to Add Check

**In bootstrap/prepare-host.sh:**
- After Proxmox detection
- Before VM creation
- Exit immediately if ZFS not found

**Error Message (User-Friendly):**
```
ERROR: PrivateBox requires Proxmox with ZFS storage

PrivateBox uses ZFS snapshots for safe, rollback-capable updates.
Your Proxmox installation appears to use LVM instead of ZFS.

To use PrivateBox:
1. Reinstall Proxmox and select "ZFS (RAID0)" during installation
2. Ensure you have at least 8GB RAM (16GB recommended)
3. Re-run this bootstrap script

For more information, see: documentation/update-architecture.md
```

## Storage Backend Configuration

### Current (LVM-based)
```bash
# bootstrap/prepare-host.sh
STORAGE="local-lvm"
```

### New (ZFS-based)
```bash
# bootstrap/prepare-host.sh
STORAGE="local-zfs"  # or detect automatically

# Auto-detection
detect_storage() {
    if pvesm status | grep -q "^local-zfs.*zfspool"; then
        echo "local-zfs"
    elif pvesm status | grep -q "^local.*dir"; then
        echo "local"  # Directory storage (legacy)
    else
        error_exit "No suitable storage found"
    fi
}
```

## Snapshot Automation (Future Implementation)

### Daily Snapshots

**Systemd Timer on Proxmox Host:**
```
# /etc/systemd/system/privatebox-daily-snapshot.timer
[Unit]
Description=Daily ZFS snapshots for PrivateBox VMs

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
```

**What Gets Snapshotted:**
- VM 100 (OPNsense): Daily
- VM 9000 (Management): Daily
- Retention: 7 daily snapshots

### Weekly Snapshots

**Systemd Timer on Proxmox Host:**
```
# /etc/systemd/system/privatebox-weekly-snapshot.timer
[Unit]
Description=Weekly ZFS snapshots for PrivateBox VMs

[Timer]
OnCalendar=weekly
OnCalendar=Sun 04:00
Persistent=true

[Install]
WantedBy=timers.target
```

**Retention:** 4 weekly snapshots (1 month history)

### Snapshot Cleanup

**Daily cleanup job removes expired snapshots:**
- Runs after daily snapshot creation
- Checks all snapshot ages
- Deletes based on retention policy
- Logs what was deleted

## Integration with Semaphore UI

### Update Templates (Future)

**Templates to Create:**
1. "Update OPNsense (Safe)" - Automatic snapshot + update + health check + rollback on failure
2. "Update Management VM (Safe)" - Same flow for VM 9000
3. "Update AdGuard Only" - Podman pull + restart + health check
4. "Rollback OPNsense" - Manual rollback to selected snapshot
5. "Rollback Management VM" - Manual rollback to selected snapshot
6. "List Snapshots" - Show all snapshots with dates/descriptions
7. "Create Manual Snapshot" - User-initiated checkpoint

### User Experience

**Happy Path (Update Succeeds):**
1. User clicks "Update OPNsense (Safe)"
2. Progress shown: "Creating snapshot... Done"
3. Progress shown: "Applying update... Done (5 minutes)"
4. Progress shown: "Running health checks... All passed"
5. Success: "OPNsense updated to 24.7.6. Rollback available for 14 days."

**Failure Path (Update Breaks):**
1. User clicks "Update OPNsense (Safe)"
2. Progress shown: "Creating snapshot... Done"
3. Progress shown: "Applying update... Done"
4. Progress shown: "Running health checks... FAILED (DNS not responding)"
5. Auto-rollback: "Health check failed, rolling back... Done"
6. Result: "Update failed and was rolled back. OPNsense restored to previous state."

**Manual Rollback:**
1. User notices issue 2 days after update
2. User clicks "Rollback OPNsense"
3. Dropdown shows: List of snapshots with dates
4. User selects: "pre-update-20251021-opnsense-24.7.5"
5. Confirmation: "This will revert OPNsense to October 21. VPN configs added after this date will be lost."
6. User confirms
7. Rollback executes in 60 seconds
8. Success: "OPNsense rolled back to October 21 snapshot"

## Update vs Recovery: When to Use What

### Use ZFS Snapshots (This Document) When:
- ✅ Update broke something
- ✅ Config change had unexpected consequences
- ✅ Want to test something and easily undo
- ✅ Service not working after change
- ✅ Need to go back 1-14 days

**Recovery time:** 60 seconds

### Use Factory Reset (recovery-system.md) When:
- ❌ System completely broken (won't boot, networking dead)
- ❌ Unknown state after many changes
- ❌ Want truly fresh start
- ❌ ZFS pool corrupted
- ❌ Multiple failed rollback attempts

**Recovery time:** 10-15 minutes

### Use Configuration Backups When:
- 📝 Want to migrate to new hardware
- 📝 Disaster recovery planning
- 📝 Compliance/audit requirements
- 📝 Testing major version upgrades

**Recovery time:** 30 minutes (reinstall + restore configs)

## Security Considerations

### Snapshot Access Control
- Snapshots readable by Proxmox root only
- No access from VMs to their own snapshots (prevents malware from deleting rollback points)
- Semaphore playbooks use Proxmox API with limited permissions

### Update Authentication
- Updates require Semaphore login (services password)
- No remote trigger capability
- Audit log of all updates and rollbacks

### Snapshot Integrity
- ZFS checksumming ensures snapshot validity
- Corrupted snapshots detected automatically
- Weekly scrub recommended (low priority, can run in background)

## Implementation Roadmap

### Phase 1: Foundation (Before FOSS Release)
- ✅ Document update architecture (this file)
- ⬜ Add ZFS requirement check to bootstrap
- ⬜ Update STORAGE variable to local-zfs
- ⬜ Test fresh Proxmox install with ZFS
- ⬜ Update CLAUDE.md with ZFS requirement

### Phase 2: Manual Snapshot Tools (FOSS Release)
- ⬜ Create manual snapshot playbook
- ⬜ Create manual rollback playbook
- ⬜ Create snapshot listing playbook
- ⬜ Add to Semaphore templates
- ⬜ Document snapshot workflow in user guide

### Phase 3: Safe Update Automation (Post-FOSS)
- ⬜ Create OPNsense safe update playbook
- ⬜ Create Management VM safe update playbook
- ⬜ Implement health check framework
- ⬜ Add automatic rollback on failure
- ⬜ Create per-service update playbooks

### Phase 4: Automated Snapshots (Product Release)
- ⬜ Implement daily snapshot timer
- ⬜ Implement weekly snapshot timer
- ⬜ Implement snapshot cleanup script
- ⬜ Add snapshot monitoring/alerting
- ⬜ Golden snapshot creation during first boot

## Testing Strategy

### Unit Tests
- ZFS detection script with various storage configurations
- Snapshot naming convention validation
- Retention policy cleanup logic

### Integration Tests
1. Fresh Proxmox install with ZFS
2. Run bootstrap (should succeed)
3. Create manual snapshot
4. Make change to OPNsense
5. Rollback snapshot
6. Verify change reverted

### Failure Tests
1. Simulated update failure (health check fails)
2. Verify automatic rollback
3. Verify system restored to working state
4. Check logs for proper error reporting

### Performance Tests
- Snapshot creation time (should be <1 second)
- Snapshot disk usage after 7 days of changes
- Rollback time for various VM sizes
- Impact on VM performance with many snapshots

## Technical Notes

### ZFS ARC Tuning (Optional)

For 16GB system with light VM usage:
```bash
# /etc/modprobe.d/zfs.conf
options zfs zfs_arc_max=4294967296  # 4GB max ARC
options zfs zfs_arc_min=1073741824  # 1GB min ARC
```

Leaves 12GB for VMs and host, 4GB for ZFS caching.

### Snapshot Space Estimation

**Conservative estimate:**
- OPNsense VM: 8GB disk, ~1GB changes per month = 1GB snapshot overhead
- Management VM: 32GB disk, ~2GB changes per month = 2GB snapshot overhead
- With 14-day retention: ~1.5GB total snapshot overhead

**256GB SSD breakdown:**
- Proxmox: ~10GB
- VMs: ~50GB
- Free space: ~196GB
- Snapshot overhead: ~5GB (1 month retention)
- **Remaining: ~191GB free** (plenty of headroom)

### ZFS Pool Health

**Recommended monitoring:**
```bash
# Weekly scrub (finds bit rot, validates checksums)
zpool scrub rpool

# Check pool status
zpool status rpool

# Check snapshot usage
zfs list -t snapshot -o name,used,refer
```

Can be automated via Semaphore playbook or systemd timer.

## Future Enhancements

Potential improvements not in initial implementation:

1. **Snapshot diffs:** Show what changed between snapshots
2. **Selective file restore:** Extract single file from snapshot
3. **Snapshot replication:** Send snapshots to external backup
4. **Cross-VM snapshots:** Atomic snapshots of multiple VMs
5. **Snapshot verification:** Automated snapshot integrity checks
6. **Update scheduling:** Time-based automatic updates with snapshots
7. **Snapshot compression:** Additional compression for long-term snapshots
8. **Notification system:** Email/alert when snapshots created/deleted

## References

- ZFS on Linux documentation: https://openzfs.github.io/openzfs-docs/
- Proxmox ZFS guide: https://pve.proxmox.com/wiki/ZFS_on_Linux
- Recovery system documentation: `documentation/recovery/recovery-system.md`
- Asset inventory: `documentation/recovery/asset-inventory.md`
