# Stage 1 Implementation Handover: FreeBSD VM Creation

## Context
You are implementing Stage 1 of the OPNsense FreeBSD bootstrap system for the PrivateBox project. This stage creates a FreeBSD VM that will later be converted to OPNsense. Note: The FreeBSD BASIC-CLOUDINIT image does NOT have cloud-init installed despite its name.

## Your Task
Create Ansible playbook `ansible/playbooks/services/opnsense-stage1-create-vm.yml` that:
1. Downloads FreeBSD 14.3 BASIC-CLOUDINIT image
2. Creates a Proxmox VM with specific configuration
3. Starts the VM (boots with DHCP)
4. Discovers VM IP via MAC address
5. Verifies VM is accessible via SSH

## Requirements

### Script Location
`bootstrap/scripts/create-opnsense-vm.sh`

### FreeBSD Image
- URL: `https://download.freebsd.org/releases/VM-IMAGES/14.3-RELEASE/amd64/Latest/FreeBSD-14.3-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz`
- Cache in: `/var/lib/vz/template/cache/`
- Extract .xz file after download
- Verify download with SHA256 if available
- Note: BASIC-CLOUDINIT variant includes cloud-init support

### VM Configuration
```bash
# Variables (configurable)
VMID=963  # Unique ID to avoid conflicts
VM_NAME="opnsense-firewall"
VM_MEMORY=4096
VM_CORES=2
VM_DISK_SIZE="32G"
VM_STORAGE="local-lvm"
WAN_BRIDGE="vmbr0"
LAN_BRIDGE="vmbr1"
FREEBSD_VERSION="14.3"
OPNSENSE_VERSION="25.7"
```

### Important: No Cloud-Init
The FreeBSD BASIC-CLOUDINIT image does NOT have cloud-init installed. The VM will:
- Boot with DHCP on vtnet0
- Use default credentials: username `freebsd`, password `freebsd`
- Not process any cloud-init configuration

### IP Discovery Process
Since we can't use cloud-init or static IP, we must discover the VM's DHCP IP:
1. Extract MAC address from VM config: `qm config 963 | grep net0`
2. Trigger ARP population: ping range of IPs in subnet
3. Find MAC in ARP table: `arp -n | grep MAC`
4. Save discovered IP to `/tmp/opnsense-vm-ip`

### VM Creation Process
1. Check if VM ID 963 exists (destroy if present)
2. Verify network bridges (vmbr0, vmbr1) exist
3. Download/verify FreeBSD 14.3 BASIC-CLOUDINIT image
4. Extract .xz compressed image
5. Create VM using `qm create`
6. Import disk with `qm importdisk`
7. Attach disk as boot device
8. Add cloud-init drive
9. Configure network (2 NICs)
10. Start VM
11. Wait for cloud-init completion

### Automated Test
After VM starts, wait 60 seconds then:
```bash
# Extract MAC from VM config
MAC=$(qm config 963 | grep net0 | sed -E 's/.*virtio=([^,]+).*/\1/')

# Populate ARP table (ping subnet range)
for ip in {1..254}; do 
  ping -c 1 -W 1 192.168.1.$ip >/dev/null 2>&1 & 
done
wait

# Find IP by MAC in ARP table
VM_IP=$(arp -n | grep -i "$MAC" | awk '{print $1}')

# Test connectivity
if ping -c 3 $VM_IP; then
  echo "✓ Stage 1 PASS - VM responds at $VM_IP"
  echo "$VM_IP" > /tmp/opnsense-vm-ip
  exit 0
else
  echo "✗ Stage 1 FAIL - VM not responding"
  exit 1
fi
```

### Integration with Existing Code
- Source configuration from `/tmp/privatebox-config.conf` if it exists
- Use password from `$ADMIN_PASSWORD` variable
- Follow patterns from `bootstrap/create-vm.sh` (Debian version)
- Use similar logging to `LOG_FILE="/tmp/privatebox-bootstrap.log"`

### Error Handling
- Check each command's exit code
- Clean up on failure (destroy VM if partially created)
- Clear error messages
- Exit codes: 0=success, 1=failure

### Example Usage
```bash
# Run directly
./bootstrap/scripts/create-opnsense-vm.sh

# Or with config
source /tmp/privatebox-config.conf
./bootstrap/scripts/create-opnsense-vm.sh
```

## Success Criteria
1. FreeBSD VM boots successfully
2. Cloud-init runs and creates test file
3. VM responds to ping on WAN interface
4. IP address saved to `/tmp/opnsense-vm-ip`
5. Exit code 0 with success message

## Important Notes
- This is Stage 1 ONLY - do not install OPNsense yet
- Keep it simple - just FreeBSD 14.3 with networking
- The VM will be converted to OPNsense 25.7 in Stage 2
- Internet connectivity required for Stage 2 bootstrap
- Must work without manual intervention
- Test must be fully automated

## Reference Files
- `bootstrap/create-vm.sh` - Existing Debian VM creation (use as template)
- `documentation/features/opnsense-freebsd-bootstrap/implementation-plan.md` - Full plan
- Stage 2 will handle the OPNsense bootstrap

## Questions to Consider
1. Should we enable QEMU guest agent?
2. Should we add serial console for debugging?
3. Do we need to enable virtio drivers?

Start by reading the existing `bootstrap/create-vm.sh` to understand the patterns, then implement the FreeBSD version following the same structure.