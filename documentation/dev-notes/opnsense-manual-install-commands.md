# OPNsense Manual Installation Commands

This document captures the command sequence for OPNsense installation automation.

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
Default: First disk (da0)
Command: qm sendkey <vmid> ret
```

**Prompt: Confirm Disk Destruction**
```
Question: Are you sure you want to destroy the current content?
Default: No (right button)
Command: qm sendkey <vmid> left  # Move to Yes
Command: qm sendkey <vmid> ret   # Confirm
```

**Error: Disk Corruption**
```
Error: "Operation is not permitted, table da0 is corrupt"
Issue: Imported/resized disk has partition table issues
Solution: Need fresh disk instead of imported IMG
```

### Notes
- USB config at da1 contains /conf/config.xml
- Main disk at da0
- Config import happens at first boot after installation