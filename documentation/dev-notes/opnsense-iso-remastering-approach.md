# OPNsense ISO Remastering Approach (Current Attempt)

## Overview
Modify OPNsense DVD ISO to embed config.xml directly, attempting 100% hands-off deployment.

## Current Implementation

### What We Built
1. Ansible playbook that:
   - Downloads OPNsense DVD ISO
   - Extracts ISO contents
   - Injects custom config.xml
   - Creates new ISO with xorriso
   - Deploys VM on Proxmox

2. Config includes:
   - Static IP configuration
   - SSH enabled with key
   - Root password set
   - Firewall rules

### The Problem
**DVD ISO is a live system, not an installer**
- Boots and runs from CD/DVD
- Doesn't automatically install to disk
- VM gets stuck: "no bootable device"

## How DVD ISOs Work

### Boot Process
1. Boot from ISO (read-only media)
2. Load system into RAM
3. Run live OPNsense
4. User must manually choose "Install"

### Why It Fails for Automation
- No automatic installation
- Requires console interaction
- Can't write to hard disk without manual steps

## What We Tried

### Attempt 1: Direct Boot
- Created VM with hard disk
- Attached custom ISO
- Result: Boots to live system, doesn't install

### Attempt 2: Boot Order
- Set boot order to CD first
- Still requires manual installation
- Not hands-off

## Potential Fixes

### 1. Auto-Install Script
- Add script to ISO that triggers installation
- Complex - need to understand OPNsense installer

### 2. Different ISO Type
- OPNsense might have auto-install ISO variant
- Not found in current offerings

### 3. Post-Boot Automation
- Boot live system
- Use qm sendkey to navigate installer
- Fragile, timing-dependent

## Lessons Learned

### What Works
- ISO modification successful
- Config.xml properly embedded
- ISO boots correctly
- xorriso preserves boot structure

### What Doesn't Work
- No automatic disk installation
- DVD ISO wrong type for this use case
- Still requires console interaction

## Conclusion
ISO remastering works but DVD format unsuitable for automated installation. Need either:
- Different image type (IMG)
- Two-ISO approach with importer
- Post-boot automation scripts