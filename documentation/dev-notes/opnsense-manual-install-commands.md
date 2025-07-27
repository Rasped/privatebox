# OPNsense Manual Installation Commands

This document captures the EXACT command sequence for OPNsense installation automation.

## CRITICAL: Order of Operations

The DVD ISO must be removed and boot order changed BEFORE the final reboot, otherwise the system will fail to boot with "no bootable device" error.

## Installation Navigation Sequence

### 1. Login as installer
```
Username: installer
Password: opnsense
Commands:
- Send each character of "installer"
- qm sendkey <vmid> ret
- Send each character of "opnsense"  
- qm sendkey <vmid> ret
```

### 2. Installer Auto-starts

**Prompt 1: Keymap Selection**
```
Default: US (United States)
Command: qm sendkey <vmid> ret
```

**Prompt 2: Installation Menu**
```
Options:
1. Install (UFS)
2. Install (ZFS)  
3. Import configuration
4. Shell
5. Reboot

To select Install (ZFS): qm sendkey <vmid> ret (first option)
To select Install (UFS): qm sendkey <vmid> down then ret
To select Import config: qm sendkey <vmid> down (3x) then ret
```

### 3. Installation Process (UFS)

**Prompt: Disk Selection**
```
NOTE: First option is cd0 (DVD), need to select da0
Command: qm sendkey <vmid> down  # Move to da0
Command: qm sendkey <vmid> ret   # Select disk
```

**Prompt: Confirm Disk Destruction**
```
Question: Are you sure you want to destroy the current content?
Default: No (right button)
Command: qm sendkey <vmid> left  # Move to Yes
Command: qm sendkey <vmid> ret   # Confirm
```

### 4. Post-Installation

**Prompt: Installation Complete**
```
Options:
1. Change root password
2. Complete Install

To skip password change: qm sendkey <vmid> down
To complete: qm sendkey <vmid> ret
```

### 5. CRITICAL: Fix Boot Configuration BEFORE Reboot

**Must Complete These Steps Before Pressing Enter to Reboot**
```
Step 1: Remove DVD ISO
Command: qm set <vmid> --ide2 none

Step 2: Set boot order to hard disk
Command: qm set <vmid> --boot order=scsi0

Step 3: NOW press enter to reboot
Command: qm sendkey <vmid> ret
```

**If you see "no bootable device" error:**
- The boot order was not changed before reboot
- Solution: qm stop <vmid> --skiplock
- Then: qm set <vmid> --boot order=scsi0
- Finally: qm start <vmid>

### Notes
- USB config at da1 contains /conf/config.xml
- Main disk at da0
- Config import process is unreliable to automate
- Alternative configuration methods needed post-installation