# OPNsense Two-ISO Deployment Approach

## Overview
Use OPNsense's native configuration importer with two separate ISOs:
1. Main OPNsense installation ISO
2. Configuration ISO containing config.xml

## How It Works

### OPNsense Importer Feature
- Built into OPNsense since v22.1.7
- Detects ISO9660 filesystems
- Looks for `/conf/config.xml` on attached media
- Runs BEFORE the live environment loads
- Activated by pressing any key during boot

### Boot Process
1. VM boots from OPNsense DVD ISO (cd0)
2. Config ISO attached as second CD (cd1)
3. During boot: "Press any key to start configuration importer"
4. Importer reads config from cd1:/conf/config.xml
5. System boots with configuration applied
6. Manual installation still required (or automate somehow)

## Implementation Steps

### 1. Create Configuration ISO
```bash
# Create directory structure
mkdir -p config-iso/conf
cp config.xml config-iso/conf/

# Create ISO
mkisofs -o opnsense-config.iso -J -R config-iso/
```

### 2. Proxmox VM Setup
```bash
# Attach both ISOs
qm set <vmid> --ide0 local:iso/OPNsense-25.7-dvd-amd64.iso,media=cdrom
qm set <vmid> --ide1 local:iso/opnsense-config.iso,media=cdrom
```

### 3. Automation Challenge
- Importer requires keypress - might use `qm sendkey`
- Installation still manual after config import
- Need to solve: automatic installation to disk

## Advantages
- Uses native OPNsense features
- No ISO modification required
- Config ISO reusable for multiple VMs
- Clean separation of concerns

## Disadvantages
- Still requires some console interaction (keypress)
- Doesn't solve automatic installation
- Two files to manage instead of one

## Potential Automation
1. **qm sendkey** to trigger importer
2. **qm sendkey** sequence to navigate installer
3. Or find way to auto-install after import

## Research Needed
- Can importer be triggered automatically?
- Can installation be scripted after config import?
- Is there a kernel parameter to auto-import?