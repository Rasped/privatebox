# OPNsense Deployment Status and Context

## Current Situation (2025-07-27)

### Infrastructure Status
- **Bootstrap VM**: Running at 192.168.1.22 (VM ID 9000)
  - Username: ubuntuadmin
  - Password: Changeme123
  - Services: Portainer (port 9000), Semaphore (port 3000)
  
- **Proxmox Host**: 192.168.1.10
  - Username: root
  - Has SSH key access from workstation

- **OPNsense VM**: ID 8000 - STUCK IN BOOT LOOP
  - Has custom ISO attached with embedded config
  - Error: "no bootable device, trying again in 1 second"
  - Problem: DVD ISO is live system, doesn't auto-install to disk

### Semaphore Status
- **URL**: http://192.168.1.22:3000
- **Admin Credentials**:
  - Username: admin  
  - Password: 89tHJP+OJmtRCJ@2@OX5ReRRw56euW-p
- **API Cookie**: Stored at `/tmp/semaphore-cookie` on workstation
- **Template ID**: 9 - "OPNsense: Deploy via Custom ISO (100% Hands-Off)"

### Task History
- Task 1: Template generation - SUCCESS
- Task 2-4: Failed - VM 8000 already existed
- Task 5-6: Failed - passlib Python module missing
- Task 7: Failed - passlib issue (was on controller, not target)
- Task 8: PARTIAL SUCCESS - ISO created but VM won't boot properly

## What We've Tried

### 1. ISO Remastering (Current Implementation)
- Successfully created custom ISO with embedded config.xml
- ISO boots but is DVD live system, not installer
- VM has no OS on disk, stuck in boot loop
- **Status**: Technically works but wrong image type

### 2. IMG Modification (Previous Attempts - Not in Code)
- Tried to modify pre-installed IMG files
- Blocked by Linux read-only UFS filesystem support
- **Status**: Abandoned due to technical limitations

### 3. Console Automation (Previous Attempts - In Git History)
- Tried qm sendkey automation
- Tried expect scripts
- Tried Python console control
- **Status**: All failed due to timing/reliability issues

## Required Information for Continuation

### SSH Key for OPNsense
**PLACEHOLDER - Must be provided**:
```
opnsense_ssh_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... ansible@privatebox"
```

### Network Configuration (Hardcoded)
- OPNsense LAN IP: 192.168.1.69/24
- Gateway: 192.168.1.3
- Root Password: PrivateBox2024!

## Next Steps to Try

### Option 1: Two-ISO Approach (Recommended)
1. Create config-only ISO with `/conf/config.xml`
2. Attach both OPNsense DVD and config ISO
3. Use OPNsense Importer feature
4. Still need to solve auto-installation

### Option 2: Fix Current Approach
1. Change from DVD ISO to VGA IMG
2. Remaster IMG instead of ISO (needs FreeBSD VM)
3. Deploy pre-installed system

### Option 3: Post-Boot Configuration
1. Deploy standard OPNsense
2. Use API/SSH to configure after boot
3. Less elegant but might be more reliable

## Quick Commands for New Context

### Reconnect to Semaphore API
```bash
curl -c /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth": "admin", "password": "89tHJP+OJmtRCJ@2@OX5ReRRw56euW-p"}' \
  http://192.168.1.22:3000/api/auth/login
```

### Clean up stuck VM
```bash
ssh root@192.168.1.10 'qm stop 8000 && qm destroy 8000'
```

### Run deployment
```bash
curl -s -b /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"template_id": 9, "project_id": 1, "environment": "{\"opnsense_ssh_key\": \"YOUR_REAL_SSH_KEY_HERE\"}"}' \
  http://192.168.1.22:3000/api/project/1/tasks
```

## File Locations
- Playbook: `/ansible/playbooks/services/opnsense-deploy-iso.yml`
- Template: `/ansible/templates/opnsense-config.xml.j2`
- Docs: `/documentation/features/opnsense-iso-remaster/`
- Dev Notes: `/documentation/dev-notes/opnsense-*.md`

## Key Learnings
1. OPNsense DVD ISOs are live systems, not installers
2. Linux can't write to UFS filesystems
3. OPNsense has built-in config importer for automation
4. Console automation is unreliable on Proxmox
5. IMG files are pre-installed, ISOs need installation

## CRITICAL: Update Before Using
1. Replace placeholder SSH key with actual key
2. Verify network IPs haven't changed
3. Check if VM 8000 still exists
4. Regenerate Semaphore cookie if expired