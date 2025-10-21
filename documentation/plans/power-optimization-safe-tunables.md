# Power optimization: Safe tunables for i226-V hardware
## Avoiding ASPM while maximizing power savings

**Status**: Planning (not yet implemented)
**Created**: 2025-10-20
**Hardware context**: Intel N150 with dual i226-V NICs
**Issue reference**: Kernel Bugzilla #218499 - i226-V ASPM broken

---

## Problem statement

**The i226-V ASPM issue:**
- PCIe Active-State Power Management (ASPM) is broken on i226-V controllers
- Enabling ASPM causes system freezes and network failures
- This is a hardware/firmware bug, unfixed as of kernel 6.17 (2025)
- **Cost**: Each i226-V NIC without ASPM costs ~1-3W extra power
- Intel N150 has **dual i226-V** NICs = **2-6W unavoidable penalty**

**However:** PowerTOP has other tunables that are safe and can save **2-5W** on top of the ASPM penalty.

For a 24/7 appliance, this matters: 5W × 24h × 365 days = 43.8 kWh/year = ~€10/year savings per unit.

---

## Safe power-saving tunables (non-NIC)

### 1. VM dirty writeback timeout ⭐ Most important

**What it does:**
Controls how often the kernel forces dirty data in RAM to be written to disk.

**Default:** 500 (5 seconds)
**Optimized:** 1500 (15 seconds)

**Why it saves power:**
Allows CPU to stay in deep sleep states (C6-C10) for 3x longer. Instead of waking every 5 seconds to write to disk, it only wakes every 15 seconds.

**For an idle firewall, this is huge.**

**Estimated savings:** 1-3W

**Command:**
```bash
echo '1500' > /proc/sys/vm/dirty_writeback_centisecs
```

**Persistent (sysctl):**
```bash
echo "vm.dirty_writeback_centisecs = 1500" >> /etc/sysctl.d/99-power-optimization.conf
sysctl -p /etc/sysctl.d/99-power-optimization.conf
```

**Safety:** Very safe. 15 seconds is still aggressive for most workloads. Data loss risk is minimal (kernel still flushes on sync/unmount).

---

### 2. SATA link power management

**What it does:**
Allows SATA link to enter low-power state when disk is idle.

**Default:** `max_performance`
**Optimized:** `min_power` or `med_power_with_dipm`

**Why it saves power:**
Reduces "chatter" on the SATA bus when disk isn't being accessed.

**Estimated savings:** 0.5-1W

**Command (find your host numbers first):**
```bash
# List SATA hosts
ls /sys/class/scsi_host/

# Apply to each host
echo 'min_power' > /sys/class/scsi_host/host0/link_power_management_policy
echo 'min_power' > /sys/class/scsi_host/host1/link_power_management_policy
```

**Persistent (udev rule):**
```bash
# /etc/udev/rules.d/99-sata-alpm.rules
ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", \
  ATTR{link_power_management_policy}="min_power"
```

**Safety:** Very safe on modern SSDs. Older spinning disks may have issues, but Intel N150 uses NVMe/SATA SSD.

---

### 3. USB autosuspend

**What it does:**
Puts USB devices and controllers into low-power state when not in use.

**Default:** Disabled (`on`)
**Optimized:** Enabled (`auto`)

**Why it saves power:**
Even if no USB devices are plugged in, the USB *controller* itself can be powered down.

**Estimated savings:** 0.5W (more on laptops with peripherals, but still meaningful)

**Command (for all USB devices):**
```bash
# Find USB devices
ls /sys/bus/usb/devices/

# Apply autosuspend to a device
echo 'auto' > /sys/bus/usb/devices/1-1/power/control

# Or apply to ALL USB devices
for device in /sys/bus/usb/devices/*/power/control; do
    echo 'auto' > "$device"
done
```

**Persistent (udev rule):**
```bash
# /etc/udev/rules.d/99-usb-autosuspend.rules
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", \
  ATTR{power/control}="auto"
```

**Safety:** Generally safe. May cause issues with some USB devices (keyboards, mice), but firewall has none.

---

### 4. Audio codec power management

**What it does:**
Puts unused audio codec chip into runtime suspend.

**Default:** `on` (always powered)
**Optimized:** `auto` (runtime PM enabled)

**Why it saves power:**
PrivateBox never uses audio. Turn off the chip.

**Estimated savings:** 0.5W

**Command (find PCI address first):**
```bash
# Find audio device
lspci | grep -i audio

# Example: 0000:00:1f.3 is common for Intel audio
echo 'auto' > /sys/bus/pci/devices/0000:00:1f.3/power/control
```

**Persistent (udev rule):**
```bash
# /etc/udev/rules.d/99-audio-pm.rules
ACTION=="add", SUBSYSTEM=="pci", ATTR{class}=="0x040300", \
  TEST=="power/control", ATTR{power/control}="auto"
```

**Safety:** Completely safe - we never use audio.

---

## What to avoid (i226-V related)

**Do not enable these tunables:**

### ❌ PCIe ASPM (active-state power management)

**Never enable this on i226-V hardware.**

**Bad commands (DO NOT RUN):**
```bash
# These will break your network:
powertop --auto-tune
echo 'powersave' > /sys/module/pcie_aspm/parameters/policy
# Kernel parameter: pcie_aspm=force
```

**Safe alternative:**
Keep ASPM disabled in BIOS or use kernel parameter `pcie_aspm=off`.

### ⚠️ NIC-specific runtime PM

**Be cautious with:**
```bash
# May break network on i226-V:
echo 'auto' > /sys/bus/pci/devices/0000:XX:XX.X/power/control  # if XX:XX.X is your NIC
```

**How to check if a PCI device is your NIC:**
```bash
lspci | grep -i ethernet
# Output example:
# 01:00.0 Ethernet controller: Intel Corporation Ethernet Controller I226-V (rev 04)
# 02:00.0 Ethernet controller: Intel Corporation Ethernet Controller I226-V (rev 04)

# DO NOT apply runtime PM to these addresses
```

---

## Implementation checklist

### Phase 1: Investigation (manual)

Run on a test Proxmox host to gather system-specific info:

```bash
# 1. Install powertop
apt install powertop

# 2. Let it calibrate (takes ~15 minutes, system will be unusable)
powertop --calibrate

# 3. Generate HTML report
powertop --html=powertop-report.html

# 4. Review report in browser
# - Go to "Tunables" section
# - Note down EXACT commands for safe tunables
# - SKIP any tunable mentioning "Ethernet" or "I226-V"

# 5. Check current values
cat /proc/sys/vm/dirty_writeback_centisecs
cat /sys/class/scsi_host/host*/link_power_management_policy
cat /sys/bus/pci/devices/*/power/control | head -20
```

**Document findings:**
- Which SATA hosts exist? (host0, host1, etc.)
- Which PCI addresses are NICs? (to exclude)
- Which PCI address is audio? (to include)
- Current power consumption baseline

### Phase 2: Create configuration script

Create `bootstrap/lib/power-optimization.sh`:

```bash
#!/bin/bash
# PrivateBox Power Optimization
# Applies safe power-saving tunables for i226-V hardware
# DOES NOT enable ASPM (broken on i226-V)

set -euo pipefail

# 1. VM Dirty Writeback (most important)
echo "Configuring VM writeback timeout..."
echo '1500' > /proc/sys/vm/dirty_writeback_centisecs

# 2. SATA Link Power Management
echo "Configuring SATA link power management..."
for host in /sys/class/scsi_host/host*/link_power_management_policy; do
    echo 'min_power' > "$host" 2>/dev/null || true
done

# 3. USB Autosuspend
echo "Enabling USB autosuspend..."
for device in /sys/bus/usb/devices/*/power/control; do
    echo 'auto' > "$device" 2>/dev/null || true
done

# 4. Audio Codec Runtime PM
echo "Enabling audio codec power management..."
for audio in /sys/bus/pci/devices/*/class; do
    if grep -q "^0x0403" "$audio"; then
        device_path=$(dirname "$audio")
        echo 'auto' > "$device_path/power/control" 2>/dev/null || true
    fi
done

# 5. Verify ASPM is disabled (safety check)
if [[ -f /sys/module/pcie_aspm/parameters/policy ]]; then
    policy=$(cat /sys/module/pcie_aspm/parameters/policy)
    if [[ "$policy" == *"[default]"* ]] || [[ "$policy" == *"[performance]"* ]]; then
        echo "✓ ASPM is safely disabled/performance mode"
    else
        echo "⚠ WARNING: ASPM may be enabled - this can break i226-V NICs"
    fi
fi

echo "✓ Power optimization applied (excluding ASPM)"
```

### Phase 3: Make persistent

Create systemd service or integrate into prepare-host.sh:

```bash
# Option A: Systemd service (runs at boot)
cat > /etc/systemd/system/privatebox-power-optimization.service <<'EOF'
[Unit]
Description=PrivateBox Power Optimization
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/privatebox-power-optimize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable privatebox-power-optimization.service
systemctl start privatebox-power-optimization.service
```

```bash
# Option B: Integrate into prepare-host.sh
# Add call to power-optimization.sh at end of prepare-host.sh
```

### Phase 4: Testing & validation

**Measure power consumption:**

```bash
# Before optimization
powertop --time=300  # Run for 5 minutes, note "Package" power

# After optimization
powertop --time=300  # Compare "Package" power

# Expected savings: 2-5W reduction
```

**Verify network stability:**

```bash
# Run continuous ping test for 24 hours
ping -i 1 8.8.8.8 | tee ping-test.log

# Check for packet loss (should be 0%)
# Check NIC status
ip link show
ethtool enp1s0  # Replace with your interface name
```

**Verify services still work:**
- Proxmox web UI accessible
- VMs start/stop normally
- Network routing works
- SSH sessions stable

---

## Expected results

### Power savings breakdown

| Tunable | Estimated Savings | Priority |
|---------|-------------------|----------|
| VM Dirty Writeback | 1-3W | ⭐⭐⭐ High |
| SATA Link PM | 0.5-1W | ⭐⭐ Medium |
| USB Autosuspend | 0.5W | ⭐ Low |
| Audio Codec PM | 0.5W | ⭐ Low |
| **Total** | **2.5-5W** | |
| **Lost to i226-V ASPM bug** | **(2-6W)** | *(Unavoidable)* |

### Annual impact (per unit)

**Optimized power savings:**
- 5W × 24h × 365 days = **43.8 kWh/year**
- At €0.25/kWh = **€10.95/year saved**
- Over 3-year appliance lifetime = **€33/unit**

**For 1000 units deployed:**
- 43,800 kWh/year saved
- €10,950/year
- €32,850 over 3 years
- **~21 tons CO₂ avoided** (EU grid average)

For a €399 appliance, this is a meaningful sustainability story.

---

## Integration points

### Where to add this

1. **prepare-host.sh** (Proxmox host setup)
   - Add power optimization during Phase 1
   - Run before VM creation
   - Create persistent configuration files

2. **Ansible playbook** (optional, for maintenance)
   - Create `ansible/playbooks/infrastructure/proxmox-power-optimize.yml`
   - Allow users to run optimization post-deployment
   - Include verification checks

3. **Documentation**
   - Add to README.md under "Advanced Topics"
   - Create dedicated guide: `documentation/power-optimization.md`
   - Mention in hardware specs (N150 power consumption)

---

## Safety & rollback

### If something breaks

**Revert all settings:**
```bash
# Restore defaults
echo '500' > /proc/sys/vm/dirty_writeback_centisecs

for host in /sys/class/scsi_host/host*/link_power_management_policy; do
    echo 'max_performance' > "$host" 2>/dev/null || true
done

for device in /sys/bus/usb/devices/*/power/control; do
    echo 'on' > "$device" 2>/dev/null || true
done

for audio in /sys/bus/pci/devices/*/class; do
    if grep -q "^0x0403" "$audio"; then
        device_path=$(dirname "$audio")
        echo 'on' > "$device_path/power/control" 2>/dev/null || true
    fi
done
```

**Disable persistent service:**
```bash
systemctl disable privatebox-power-optimization.service
systemctl stop privatebox-power-optimization.service
```

### Risk assessment

| Tunable | Risk Level | Failure Mode |
|---------|-----------|--------------|
| VM Writeback | Low | Slightly increased data loss risk on sudden power loss |
| SATA Link PM | Very Low | Possible SSD compatibility issues (rare) |
| USB Autosuspend | Low | USB device may not wake (not applicable - no peripherals) |
| Audio PM | None | Audio doesn't work (don't need it anyway) |

**Overall risk:** Very low for headless firewall appliance.

---

## Marketing/sustainability angle

**For product page:**

> "PrivateBox is optimized for 24/7 operation with intelligent power management. Our software automatically applies safe power-saving features that reduce energy consumption by up to 5W (~€11/year savings) without compromising network performance or reliability."

**For technical specs:**

> "Typical power consumption: 8-12W idle (after optimization)
> Annual energy cost: ~€20-30 (at €0.25/kWh)
> CO₂ footprint: ~9kg/year (EU grid average)"

---

## ASPM auto-detection: Should we implement?

### The question

Since ASPM is broken on Intel i225-V/i226-V NICs but works fine on other PCIe devices (NVMe, USB controllers, etc.), should we:
- **Auto-detect** known-broken NICs and skip ASPM only on those devices?
- Or leave ASPM entirely to **user control** with documentation?

### Arguments for auto-detection

**Pros:**
1. ✅ **Better UX** - "Just works" for most users, no manual configuration needed
2. ✅ **Safety** - Prevents accidental network breakage from enabling ASPM globally
3. ✅ **Maximizes power savings** - ASPM still works on non-NIC PCIe devices (NVMe, USB3 controllers, etc.)
4. ✅ **Professional product behavior** - Commercial appliances should handle edge cases automatically
5. ✅ **We know the hardware** - Intel N150 BOM is fixed (dual i226-V), we can be specific
6. ✅ **Selective optimization** - Get ASPM benefits everywhere except the broken NICs
7. ✅ **Reduces support burden** - Users won't break their network and file tickets

**Cons:**
1. ❌ **Added complexity** - Need to maintain PCI device ID blacklist
2. ❌ **False positives** - Might block hardware that works fine (newer firmware, future kernels)
3. ❌ **Future-proofing issues** - What if Intel fixes it in kernel 6.20? We'd block unnecessarily
4. ❌ **Hardware variations** - i225-V rev1 vs rev3 vs i226-V vs i226-IT - which revisions are broken?
5. ❌ **Maintenance burden** - Need to update device list as new problematic models appear
6. ❌ **Testing overhead** - Need to test on actual hardware with these NICs

### Arguments for user control (documentation only)

**Pros:**
1. ✅ **Simpler code** - Document the issue, provide commands, let users decide
2. ✅ **Flexibility** - Users can test if newer kernels fix the issue without code changes
3. ✅ **No false positives** - Don't block potentially working setups (newer firmware, fixed kernels)
4. ✅ **Less maintenance** - No device ID list to maintain or update
5. ✅ **Transparency** - Users understand exactly what's happening and why
6. ✅ **Standard Linux approach** - Document workarounds, users apply them (Arch/Debian model)

**Cons:**
1. ❌ **User confusion** - "Why isn't my system optimized?" "Why manual steps?"
2. ❌ **Support burden** - Users enable ASPM globally, break network, blame PrivateBox
3. ❌ **Missed optimization** - Users may not enable ASPM even on safe devices (NVMe, etc.)
4. ❌ **Professional polish** - Commercial appliance should "just work" without manual tuning
5. ❌ **Inconsistent experience** - Some users optimize, others don't

### Hybrid approach (recommended)

**Auto-detect known-broken NICs, but provide user override for testing/future fixes.**

**Implementation concept:**

```bash
# Known broken Intel 2.5GbE NICs (as of 2025)
BROKEN_NIC_IDS=(
    "8086:125c"  # i226-V
    "8086:0d9f"  # i225-LM
    "8086:15f2"  # i225-V rev 1
    "8086:15f3"  # i225-V rev 2/3
    "8086:1a1d"  # i226-LM
    "8086:1a1e"  # i226-IT
)

detect_broken_nics() {
    for device_id in "${BROKEN_NIC_IDS[@]}"; do
        if lspci -nn | grep -q "$device_id"; then
            return 0  # Found broken NIC
        fi
    done
    return 1  # No broken NICs
}

apply_aspm_policy() {
    if detect_broken_nics; then
        log "⚠ Detected Intel 2.5GbE NIC with known ASPM bug"
        log "  Skipping ASPM (prevents network failures)"
        log "  Reference: Kernel Bugzilla #218499"

        # User override via config file
        if [[ "${PRIVATEBOX_FORCE_ASPM:-0}" == "1" ]]; then
            log "  OVERRIDE: User forced ASPM enable via config"
            enable_aspm_globally
        else
            log "  ASPM disabled (override: set PRIVATEBOX_FORCE_ASPM=1)"
            disable_aspm
        fi
    else
        log "✓ No problematic NICs detected"
        log "  Enabling ASPM for maximum power savings"
        enable_aspm_globally
    fi
}
```

**Configuration file:**
```bash
# /etc/privatebox/power-optimization.conf

# Force enable ASPM even on known-broken Intel 2.5GbE NICs
# WARNING: May cause network failures on i225-V/i226-V
# Only enable if you have updated firmware or kernel fix
PRIVATEBOX_FORCE_ASPM=0
```

**Benefits of hybrid:**
- Default safe behavior (auto-detect and skip)
- Advanced users can override for testing
- Future-proof (when kernel fixes it, users can enable)
- Clear logging explains what's happening and why
- Commercial polish + technical flexibility

### Context: PrivateBox is a commercial appliance

**Key considerations:**
1. **€399 price point** - Customers expect professional, reliable behavior
2. **Fixed BOM** - Intel N150 always has dual i226-V, we know the hardware
3. **Support burden matters** - Direct-to-consumer model, no phone support
4. **Target audience** - Mix of technical enthusiasts (who understand) and consumers (who just want it to work)
5. **24/7 operation** - Network failure = major customer incident
6. **Competition** - Firewalla/Ubiquiti "just work" without manual optimization

**This differs from general-purpose Linux:**
- Arch/Ubuntu support infinite hardware combinations → can't auto-detect everything
- DIY users expect to read wikis and apply workarounds
- PrivateBox customers expect appliance behavior

### Additional considerations

**1. Scope of ASPM benefits**

ASPM doesn't just affect NICs - it affects ALL PCIe devices:
- NVMe SSDs (can save 0.5-1W)
- USB3 controllers (can save 0.3-0.5W)
- Audio codecs (can save 0.2-0.3W)
- Other add-in cards

**If we globally disable ASPM due to NICs, we lose 1-2W of savings elsewhere.**

**Selective ASPM (per-device) is technically possible but complex:**
```bash
# Enable ASPM for specific non-NIC devices
echo 'auto' > /sys/bus/pci/devices/0000:00:14.0/power/control  # USB controller
echo 'auto' > /sys/bus/pci/devices/0000:02:00.0/power/control  # NVMe drive
# Skip the NIC devices at 0000:01:00.0 and 0000:03:00.0
```

This requires per-device enumeration, which is exactly what auto-detection solves.

**2. Hardware revision detection**

Not all i225-V revisions are broken:
- **i225-V rev 1, 2** - Known issues with disconnects
- **i225-V rev 3** - Most issues fixed (but ASPM may still be problematic)
- **i226-V** - ASPM power management crashes system (confirmed)

**Should we check revision?**
```bash
# Get revision
lspci -vnn | grep -A 1 "I225-V"
# Output: Kernel driver in use: igc
#         Subsystem: ... [8086:0000]

# Problem: Revision not always exposed via lspci
# May need to check: /sys/bus/pci/devices/.../revision
```

**Decision: Blacklist all i225/i226 variants** unless user explicitly overrides. Conservative approach for commercial product.

**3. Testing requirements**

If we implement auto-detection, we MUST test on:
- ✅ Intel N150 with dual i226-V (our target hardware)
- ⚠️ Other hardware WITHOUT i226-V (ensure ASPM still enabled)
- ⚠️ Verify network stability over 48+ hours with ASPM disabled
- ⚠️ Measure actual power savings with/without ASPM on non-NIC devices

**Lab hardware needed:**
- Intel N150 (have)
- Non-Intel hardware for comparison (don't have?)

**4. Maintenance over time**

**What happens when:**
- Kernel 6.25 fixes the i226-V ASPM bug?
- Intel releases i227-V with same issue?
- Firmware update fixes it for specific motherboard models?

**Maintenance scenarios:**

| Scenario | Auto-Detect Approach | User Control Approach |
|----------|---------------------|----------------------|
| Kernel fixes bug | Need to update docs: "kernel 6.25+ users can override" | User just enables ASPM, tests |
| New broken NIC model | Need to update blacklist in code | User adds to their local config |
| Firmware fixes specific boards | Override per-board? Complex. | User tests, enables if works |

**Verdict:** User control is lower maintenance long-term, but auto-detect provides better initial UX.

### Recommendation

**For PrivateBox: Implement auto-detection with override (Hybrid Approach)**

**Rationale:**
1. **Commercial product expectations** - Should work out of box without manual tuning
2. **Known hardware** - We control the BOM (Intel N150), can be specific
3. **Safety first** - Prevent network failures that would generate support tickets
4. **Maximize savings** - Still get ASPM benefits on non-NIC devices
5. **Documented override** - Power users can test future fixes
6. **Professional polish** - Shows attention to detail and hardware-specific optimization

**Implementation priority:** Medium (after core functionality works)

**Alternative for MVP:** Document only, implement auto-detect in v2.0 after field testing.

## Open questions

1. **When to apply?**
   - During initial bootstrap? (user gets optimized system from day 1)
   - As optional Semaphore playbook? (user opts in)
   - Default on, with opt-out? (commercial appliance should be optimized)

2. **How to measure effectiveness?**
   - Include power monitoring in health checks?
   - Log powertop snapshots periodically?
   - Telemetry (if we add opt-in analytics)?

3. **Hardware variations:**
   - Will this work on non-N150 hardware?
   - What if user replaces with different NIC?

4. **User control:**
   - Expose tunables in web UI? (advanced users)
   - Document manual override procedures?

---

## Decision log

**2025-10-20**: Initial planning based on community feedback
- Identified safe tunables that avoid i226-V ASPM issue
- Estimated 2.5-5W savings available
- Documented implementation approach
- No implementation yet - needs testing first

**2025-10-20**: ASPM auto-detection design session
- Analyzed trade-offs between auto-detection vs user control
- Documented hybrid approach (auto-detect with override)
- Recommendation: Implement auto-detection for commercial product
- **Decision: Document only, defer implementation**
- Rationale: Need field testing first, can add in v2.0
- For MVP: Document the issue in README, provide manual workaround commands

**Next Steps:**
- Test safe tunables (non-ASPM) on Intel N150 hardware
- Measure baseline vs optimized power consumption (VM writeback, SATA PM, USB, audio)
- Verify network stability over 48+ hours
- Create implementation script for safe tunables only
- Defer ASPM auto-detection to v2.0 after user feedback

---

## References

- Kernel Bugzilla #218499: https://bugzilla.kernel.org/show_bug.cgi?id=218499
- Intel i226-V datasheet (power specs)
- PowerTOP documentation: https://github.com/fenrus75/powertop
- Arch Wiki Power Management: https://wiki.archlinux.org/title/Power_management
- Community discussion thread (source of analysis above)
