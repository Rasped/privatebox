# Two-Phase OPNsense Deployment Plan
## Enabling "Verified Path" Installation

**Status**: Planning (Not Yet Implemented)
**Created**: 2025-10-20
**Goal**: Allow users to manually install OPNsense from official ISO for trust verification

---

## Problem Statement

**Current Flow:**
```
Clean Proxmox → Quickstart → Downloads pre-built OPNsense template
```

**Trust Issue:** Users must trust SubRosa's pre-built OPNsense image.

**Desired Flow:**
```
Clean Proxmox → Quickstart Phase 1 → User installs OPNsense manually → Quickstart Phase 2
```

**Why This Works:**
- User downloads and verifies official OPNsense ISO
- User controls the base installation
- Quickstart adds network configuration only
- Same secure end state (VLAN 20 isolation)

---

## Technical Constraint

**The Chicken-and-Egg Problem:**
- Clean Proxmox has only vmbr0 (WAN bridge)
- OPNsense needs vmbr1 (LAN bridge) for dual-interface setup
- Can't create dual-NIC VM without both bridges existing
- Can't remotely access single-NIC OPNsense (SSH disabled on WAN)

**Solution:** Split quickstart into two phases:
1. **Phase 1**: Prepare Proxmox infrastructure (create vmbr1)
2. **User Action**: Manually install OPNsense on VM 100
3. **Phase 2**: Detect and configure OPNsense, deploy services

---

## User Experience

### Path A: Fast/Convenient (Current)
```bash
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/.../quickstart.sh | bash"
```
- Downloads pre-built OPNsense template
- ~15 minutes to full deployment
- User trusts SubRosa image

### Path B: Verified/Trusted (New)
```bash
# Step 1: Prepare infrastructure
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/.../quickstart.sh | bash -s -- --prepare-only"

# Output:
# ✓ Proxmox infrastructure prepared
# ✓ vmbr1 created on second NIC
# ✓ VLAN 20 interface configured
#
# Next: Install OPNsense manually
# See: https://docs.privatebox.local/manual-opnsense-install
#
# After OPNsense is installed, run:
# ssh root@192.168.1.10 "curl -fsSL .../quickstart.sh | bash -s -- --continue"

# Step 2: User installs OPNsense from official ISO
# (User downloads, verifies checksums, installs via Proxmox UI or CLI)
# IMPORTANT: Use default password "opnsense" during install

# Step 3: Complete deployment
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/.../quickstart.sh | bash -s -- --continue"

# Output:
# ✓ Detected OPNsense at 10.10.10.1
# ✓ Configuring VLAN 20 via SSH...
# ✓ Management VM deployed
# ✓ Full deployment complete (~20 minutes)
```

### Key Simplifications

**What makes this REALLY simple:**

1. **Default password** - User just uses "opnsense" (no password prompts)
2. **Config.xml upload** - We already have this working in deploy-opnsense.sh
3. **Automatic detection** - Script checks 10.10.20.1 then 10.10.10.1
4. **Single reboot max** - Only if needed, most likely works without
5. **Automatic backup** - Config saved before any changes
6. **Idempotent** - Safe to re-run Phase 2 multiple times

**User only needs to:**
1. Run Phase 1 command
2. Install OPNsense from official ISO (with defaults)
3. Run Phase 2 command

**That's it!** No complex networking knowledge required.

---

## Implementation Plan

### 1. Quickstart Script Changes

**New command-line arguments:**
```bash
quickstart.sh                    # Default: full automated deployment (Path A)
quickstart.sh --prepare-only     # Phase 1: Infrastructure prep only (Path B)
quickstart.sh --continue         # Phase 2: Detect and configure (Path B)
```

**Detection logic on startup:**
```bash
# Check if we're resuming a two-phase install
if [[ -f /tmp/privatebox-phase1-complete ]]; then
    # Phase 1 already done, default to --continue
    MODE="continue"
elif [[ "$1" == "--prepare-only" ]]; then
    MODE="prepare"
elif [[ "$1" == "--continue" ]]; then
    MODE="continue"
else
    MODE="full"  # Standard automated deployment
fi
```

### 2. Phase 1: Infrastructure Preparation

**What Phase 1 Does:**
```bash
prepare_phase() {
    run_preflight_checks()
    generate_ssh_keys()
    detect_wan_bridge()
    setup_network_bridges()      # Creates vmbr1 with VLAN-aware
    configure_services_network()  # Creates vmbr1.20 with 10.10.20.20/24
    generate_https_certificate()
    generate_config()

    # Create marker file
    touch /tmp/privatebox-phase1-complete

    display_phase1_summary()
}
```

**Phase 1 Output:**
```
======================================
  PrivateBox Infrastructure Ready
======================================

Proxmox Configuration:
  ✓ vmbr0 (WAN): Connected to internet
  ✓ vmbr1 (LAN): Ready on second NIC
  ✓ VLAN 20 (Services): 10.10.20.20/24

Next Steps:
1. Install OPNsense manually from official ISO
2. Create VM with ID 100:
   - CPU: 2 cores
   - RAM: 2GB
   - Disk: 16GB
   - Net0: Bridge=vmbr0 (WAN)
   - Net1: Bridge=vmbr1 (LAN)

3. During OPNsense installation:
   - WAN: DHCP on vtnet0
   - LAN: 10.10.10.1/24 on vtnet1
   - Enable SSH
   - **Set root password to: opnsense (use default)**

4. After installation, run:
   curl -fsSL https://.../quickstart.sh | bash -s -- --continue

Documentation: https://docs.privatebox.local/manual-install
======================================
```

### 3. Phase 2: Detection and Configuration

**OPNsense Detection Logic:**
```bash
detect_opnsense() {
    # Option 1: Pre-configured with VLAN 20 (template path)
    if ssh_test root@10.10.20.1; then
        echo "✓ Found OPNsense with VLAN 20 configured"
        OPNSENSE_IP="10.10.20.1"
        OPNSENSE_NEEDS_CONFIG=false
        return 0
    fi

    # Option 2: Manual install, LAN only (verified path)
    if ssh_test root@10.10.10.1; then
        echo "✓ Found OPNsense at 10.10.10.1 (needs VLAN configuration)"
        OPNSENSE_IP="10.10.10.1"
        OPNSENSE_NEEDS_CONFIG=true
        return 0
    fi

    # Option 3: No OPNsense found
    return 1
}
```

**VLAN 20 Configuration Function:**
```bash
configure_opnsense_vlan20() {
    display "Configuring VLAN 20 on OPNsense via SSH..."

    # 1. Backup existing config with timestamp
    sshpass -p opnsense ssh -o StrictHostKeyChecking=no root@10.10.10.1 \
        "cp /conf/config.xml /conf/config.xml.pre-vlan20-$(date +%Y%m%d-%H%M%S)"

    # 2. Upload VLAN 20 configuration snippet
    # Use config.xml manipulation (same approach as deploy-opnsense.sh:533)
    upload_vlan20_config

    # 3. Apply configuration without reboot (test required)
    sshpass -p opnsense ssh -o StrictHostKeyChecking=no root@10.10.10.1 \
        "configctl interface reconfigure"

    # 4. Wait for VLAN to come up (or fallback to reboot if needed)
    if ! wait_for_vlan20 30; then
        display "  VLAN 20 not responding, attempting reboot..."
        qm reboot 100
        wait_for_opnsense_reboot
        wait_for_vlan20 60 || error_exit "VLAN 20 failed to activate"
    fi

    # 5. Update OPNSENSE_IP for subsequent operations
    OPNSENSE_IP="10.10.20.1"

    display "✓ VLAN 20 configured successfully at 10.10.20.1"
}
```

**Phase 2 Flow:**
```bash
continue_phase() {
    # Load config from Phase 1
    source /tmp/privatebox-config.conf

    # Detect OPNsense
    if ! detect_opnsense; then
        error_exit "No OPNsense found. Install OPNsense on VM 100 first."
    fi

    # Configure VLAN 20 if needed
    if [[ "$OPNSENSE_NEEDS_CONFIG" == "true" ]]; then
        configure_opnsense_vlan20
    fi

    # Continue with normal deployment
    deploy_management_vm()
    verify_installation()
    display_final_summary()
}
```

### 4. VLAN 20 Configuration Details

**Method: Config.xml Manipulation**

Use the same approach as `deploy-opnsense.sh:533` - upload full config.xml with VLAN 20 pre-configured.

```bash
configure_vlan20_via_config() {
    display "Uploading VLAN 20 configuration..."

    # 1. Backup existing config with timestamp
    sshpass -p opnsense ssh -o StrictHostKeyChecking=no root@10.10.10.1 \
        "cp /conf/config.xml /conf/config.xml.pre-vlan20-$(date +%Y%m%d-%H%M%S)"

    display "  ✓ Config backup created"

    # 2. Upload config.xml with VLAN 20 (from bootstrap/configs/opnsense/config.xml)
    #    This file already has VLAN 20 configured as vlan01 interface
    sshpass -p opnsense scp -o StrictHostKeyChecking=no \
        "${SCRIPT_DIR}/configs/opnsense/config.xml" \
        root@10.10.10.1:/conf/config.xml

    display "  ✓ Configuration uploaded"

    # 3. Apply configuration (test if this works without reboot)
    sshpass -p opnsense ssh -o StrictHostKeyChecking=no root@10.10.10.1 \
        "configctl interface reconfigure"

    display "  ✓ Configuration applied"

    # 4. Test if VLAN 20 came up
    sleep 10
    if ping -c 1 -W 2 10.10.20.1 &>/dev/null; then
        display "  ✓ VLAN 20 is responding at 10.10.20.1"
        return 0
    else
        display "  ⚠ VLAN 20 not responding, reboot required"
        # Fallback: reboot to ensure VLAN configuration applies
        qm reboot 100
        wait_for_opnsense_reboot
        return 1
    fi
}
```

**Testing Required:**
- ⚠️ **Verify** that `configctl interface reconfigure` activates VLAN 20 without reboot
- Test on clean OPNsense 25.7 installation
- If reboot is required, update code to use reboot path by default
- Document timing: no-reboot (~10s) vs reboot (~90s)

### 5. Error Handling

**Common failure scenarios:**

1. **VM 100 doesn't exist:**
   ```
   ERROR: VM 100 not found
   Install OPNsense on VM 100 before running --continue
   See: https://docs.privatebox.local/manual-install
   ```

2. **VM 100 exists but not running:**
   ```
   ERROR: VM 100 is stopped
   Starting VM 100...
   Waiting for OPNsense to boot...
   ```

3. **OPNsense not at expected IPs:**
   ```
   ERROR: Cannot connect to OPNsense
   Checked:
     - 10.10.20.1 (VLAN 20) - No response
     - 10.10.10.1 (LAN) - No response

   Possible issues:
     - OPNsense not configured with LAN at 10.10.10.1
     - SSH not enabled
     - VM network interfaces not correctly assigned
   ```

4. **Wrong password:**
   ```
   ERROR: SSH authentication failed
   Please ensure:
     - SSH is enabled in OPNsense
     - You can login with root password

   Test manually: ssh root@10.10.10.1
   ```

5. **VLAN configuration fails:**
   ```
   ERROR: Failed to configure VLAN 20
   OPNsense is still accessible at 10.10.10.1
   Config backup saved at /conf/config.xml.pre-vlan20

   You can:
     1. Retry: quickstart.sh --continue
     2. Manual config: See troubleshooting guide
   ```

### 6. User Documentation

**New documentation needed:**

#### `documentation/manual-opnsense-install.md`
```markdown
# Manual OPNsense Installation Guide

## Why Install Manually?

Manual installation allows you to:
- Download and verify official OPNsense ISO
- Control the base installation
- Trust the firewall foundation

## Prerequisites

- Proxmox infrastructure prepared (Phase 1 complete)
- OPNsense ISO downloaded and verified

## Step-by-Step Guide

### 1. Download OPNsense ISO

Download from: https://opnsense.org/download/
Current version: 25.7

Verify checksum:
```bash
sha256sum OPNsense-25.7-dvd-amd64.iso
# Compare with published checksum
```

### 2. Upload ISO to Proxmox

```bash
scp OPNsense-25.7-dvd-amd64.iso root@192.168.1.10:/var/lib/vz/template/iso/
```

### 3. Create VM 100

Via Proxmox UI:
- VM ID: 100
- Name: privatebox-opnsense
- ISO: OPNsense-25.7-dvd-amd64.iso
- CPU: 2 cores
- RAM: 2048 MB
- Disk: 16 GB
- Network Device (net0): Bridge=vmbr0 (WAN)
- Network Device (net1): Bridge=vmbr1 (LAN)

Or via CLI:
```bash
qm create 100 --name privatebox-opnsense \
  --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --net1 virtio,bridge=vmbr1 \
  --cdrom local:iso/OPNsense-25.7-dvd-amd64.iso
```

### 4. Install OPNsense

Start VM and connect to console:
```bash
qm start 100
qm terminal 100
```

During installation:
- Install to disk
- **Set root password: `opnsense` (use default)**
- Configure interfaces:
  - vtnet0 = WAN (DHCP)
  - vtnet1 = LAN (10.10.10.1/24)
- Enable SSH

**IMPORTANT:** Use default OPNsense credentials (root/opnsense) to ensure Phase 2 can connect automatically. You will change this password after deployment is complete.

### 5. Verify Installation

After reboot, test SSH access:
```bash
ssh root@10.10.10.1
# Should prompt for password
```

### 6. Continue Deployment

```bash
ssh root@192.168.1.10 "curl -fsSL https://.../quickstart.sh | bash -s -- --continue"
```

## Troubleshooting

[Common issues and solutions...]
```

---

## Testing Strategy

### Test Case 0: VLAN 20 Without Reboot (CRITICAL)
```bash
# Clean Proxmox, clean OPNsense installed manually
# Run Phase 1
# Run Phase 2 with VLAN 20 config
# Test if `configctl interface reconfigure` activates VLAN 20
# Measure timing: success or needs reboot?
# Update code based on results
```
**⚠️ THIS TEST MUST BE DONE BEFORE IMPLEMENTATION**

### Test Case 1: Path A (Automated)
```bash
# Clean Proxmox
# Run full deployment
# Verify: OPNsense deployed from template, VLAN 20 works
```

### Test Case 2: Path B (Manual Install - Happy Path)
```bash
# Clean Proxmox
# Run Phase 1: --prepare-only
# Manually install OPNsense (correct config)
# Run Phase 2: --continue
# Verify: VLAN 20 created, services deployed
```

### Test Case 3: Path B (Wrong OPNsense Config)
```bash
# Clean Proxmox
# Run Phase 1
# Install OPNsense with LAN = 192.168.1.x (WRONG)
# Run Phase 2
# Verify: Proper error message, clear guidance
```

### Test Case 4: Path B (No SSH Enabled)
```bash
# Clean Proxmox
# Run Phase 1
# Install OPNsense without enabling SSH
# Run Phase 2
# Verify: Detects SSH failure, provides guidance
```

### Test Case 5: Resume After Failure
```bash
# Phase 2 fails during VLAN config
# Fix issue manually
# Re-run Phase 2: --continue
# Verify: Idempotent, doesn't break existing config
```

---

## File Changes Required

### New Files
- `documentation/plans/two-phase-opnsense-deployment.md` (this file)
- `documentation/manual-opnsense-install.md` (user guide)
- `bootstrap/lib/opnsense-vlan-config.sh` (VLAN 20 configuration functions)

### Modified Files
- `quickstart.sh`: Add argument parsing for --prepare-only and --continue
- `bootstrap/bootstrap.sh`: Add phase detection and routing logic
- `bootstrap/deploy-opnsense.sh`: Add detection logic for existing OPNsense
- `bootstrap/lib/opnsense-vlan-config.sh`: Extract VLAN configuration to separate module

### Configuration Files
- `/tmp/privatebox-phase1-complete`: Marker file for phase tracking
- `/tmp/privatebox-config.conf`: Shared config between phases (already exists)

---

## Timeline Estimate

**Implementation: 1-2 days**
- Phase 1 logic: 2-3 hours (mostly refactoring existing code)
- Detection logic: 3-4 hours (SSH testing, error handling)
- VLAN 20 configuration: 4-6 hours (XML manipulation, testing)
- Error handling: 2-3 hours
- Testing: 4-6 hours (multiple scenarios)

**Documentation: 4-6 hours**
- User guide for manual installation
- Updated quickstart documentation
- Troubleshooting guide

**Total: 2-3 days of focused work**

---

## Security Considerations

**Phase 1 creates infrastructure:**
- vmbr1 exists but no VMs attached yet
- VLAN 20 exists but no gateway yet
- Low risk: isolated network, no services

**User installs OPNsense:**
- User controls ISO verification
- User sets root password
- Potential for misconfiguration (handled by Phase 2 detection)

**Phase 2 configures VLAN:**
- Needs root password (user must provide)
- Creates VLAN 20 via SSH (standard OPNsense config)
- End state identical to template path

**Trust model:**
- User verifies base OS (OPNsense)
- Quickstart adds network config (observable, auditable)
- End result: same secure architecture as template path

---

## Decisions Made

1. **Password handling**: ✅ **RESOLVED**
   - User sets root password to `opnsense` (default) during manual install
   - Phase 2 uses `sshpass -p opnsense` to connect
   - Password changed via Semaphore playbook after full deployment
   - Simple, no user prompts needed

2. **VLAN 20 configuration method**: ✅ **RESOLVED**
   - Use config.xml manipulation (like deploy-opnsense.sh line 533)
   - More reliable, matches existing pattern
   - Already have proven code for this approach

3. **Reboot requirement**: ⚠️ **NEEDS TESTING**
   - Assumption: VLAN should come up without reboot using `configctl interface reconfigure`
   - **TEST REQUIRED:** Verify VLAN 20 activates without reboot on OPNsense 25.7
   - Fallback: If reboot needed, use `qm reboot 100` and wait (~90 seconds)

4. **Idempotency**: ✅ **RESOLVED**
   - Always detect VLAN 20 first before attempting configuration
   - Check both 10.10.20.1 (VLAN exists) and 10.10.10.1 (VLAN needs creation)
   - Safe to re-run Phase 2 multiple times

5. **Backup**: ✅ **RESOLVED**
   - Always backup config.xml before modifications
   - Pattern: `cp /conf/config.xml /conf/config.xml.pre-vlan20-$(date +%Y%m%d-%H%M%S)`
   - Document rollback procedure in user guide

---

## Decision Log

**2025-10-20**: Initial planning complete
- Option 1 selected: Two-phase approach
- Will implement VLAN 20 configuration via SSH
- Requires comprehensive error handling
- Estimated 2-3 days implementation + testing

**2025-10-20**: Key decisions finalized
- ✅ Password: Use default `opnsense` password for simplicity
- ✅ Config method: Use config.xml manipulation (proven approach)
- ✅ Backup: Always create timestamped backup before changes
- ✅ Idempotency: Detect VLAN 20 first, skip if exists
- ⚠️ Reboot: Assume not needed, test `configctl interface reconfigure`, fallback to reboot if required

**Next Steps:**
- Test VLAN 20 creation without reboot on OPNsense 25.7
- Implement detection and configuration logic
- Create comprehensive user documentation
- Test all error scenarios

---

## Success Criteria

**User Experience:**
- [ ] Clear separation between automated and verified paths
- [ ] Helpful error messages for common mistakes
- [ ] Documentation covers all scenarios

**Technical:**
- [ ] Phase 1 prepares infrastructure correctly
- [ ] Phase 2 detects OPNsense reliably
- [ ] VLAN 20 configuration works consistently
- [ ] Idempotent: can re-run without breaking
- [ ] End state identical to template path

**Security:**
- [ ] User can verify OPNsense ISO checksums
- [ ] User controls base installation
- [ ] VLAN isolation maintained
- [ ] No security regression vs template path
