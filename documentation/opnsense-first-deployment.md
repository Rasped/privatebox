# OPNsense-First Deployment Guide

## Overview

This document provides the step-by-step deployment guide for PrivateBox using the OPNsense-first approach, where the firewall is established before any services. The approach prioritizes security by establishing the firewall first, then deploying all services behind it.

## Prerequisites

- Fresh Proxmox installation
- Two physical NICs configured:
  - NIC1 → vmbr0 (WAN)
  - NIC2 → vmbr1 (LAN, VLAN-aware)
- Access to Proxmox web UI or SSH
- Internet connectivity for downloading images

## Phase 1: Prepare OPNsense VM

### Step 1.1: Download OPNsense Image
```bash
# SSH to Proxmox
ssh root@<proxmox-ip>

# Download OPNsense ISO
cd /var/lib/vz/template/iso/
wget https://mirror.dns-root.de/opnsense/releases/24.7/OPNsense-24.7-dvd-amd64.iso.bz2
bunzip2 OPNsense-24.7-dvd-amd64.iso.bz2
```

### Step 1.2: Create OPNsense VM
```bash
# Create VM (ID 100)
qm create 100 --name opnsense --memory 4096 --cores 2 --sockets 1

# Configure boot disk
qm set 100 --scsi0 local-lvm:32 --scsihw virtio-scsi-pci --bootdisk scsi0

# Add network interfaces (WAN first, LAN second - ORDER MATTERS!)
qm set 100 --net0 virtio,bridge=vmbr0  # WAN
qm set 100 --net1 virtio,bridge=vmbr1  # LAN

# Attach ISO
qm set 100 --ide2 local:iso/OPNsense-24.7-dvd-amd64.iso,media=cdrom

# Set boot order
qm set 100 --boot order=ide2
```

### Step 1.3: Initial OPNsense Configuration
```bash
# Start VM
qm start 100

# Connect via console
qm terminal 100

# During installation:
# - Install to hard disk
# - Default settings for most options
# - Reboot when complete
```

### Step 1.4: Configure OPNsense Interfaces
After reboot, in OPNsense console:
```
1) Assign interfaces:
   - WAN: vtnet0 (vmbr0)
   - LAN: vtnet1 (vmbr1)

2) Set LAN IP:
   - IP: 10.10.10.1
   - Subnet: 24
   - No DHCP for now

3) Enable SSH on LAN:
   - Option 11 (Reload all services)
   - SSH will be available on LAN
```

## Phase 2: Configure VLANs in OPNsense

### Step 2.1: Access OPNsense
```bash
# From Proxmox, access OPNsense via LAN IP
ssh root@10.10.10.1
# Default password: opnsense
```

### Step 2.2: Apply Configuration Template
```bash
# Copy prepared config (from your workstation)
scp /path/to/config.xml root@10.10.10.1:/conf/config.xml

# Apply configuration
configctl firmware restart
```

The config.xml includes:
- All VLANs (20-70) configured
- Firewall rules for inter-VLAN communication
- DHCP servers for each VLAN
- DNS pointing to 10.10.20.10

### Step 2.3: Verify VLAN Configuration
```bash
# Check interfaces
ifconfig | grep vlan

# Should see:
# vlan00 (VLAN 20 - Services)
# vlan01 (VLAN 30 - Guest)
# ... etc
```

## Phase 3: Deploy Management VM

### Step 3.1: Prepare Cloud-Init Image
```bash
# On Proxmox
cd /tmp

# Download Debian 13 cloud image
wget https://cloud.debian.org/debian/daily/latest/debian-13-generic-amd64-daily.qcow2

# Create VM (ID 200)
qm create 200 --name management-vm --memory 4096 --cores 2

# Import disk
qm importdisk 200 debian-13-generic-amd64-daily.qcow2 local-lvm

# Configure VM
qm set 200 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-200-disk-0
qm set 200 --boot c --bootdisk scsi0
qm set 200 --serial0 socket --vga serial0
qm set 200 --net0 virtio,bridge=vmbr1,tag=20  # VLAN 20 tagged!
```

### Step 3.2: Configure Cloud-Init for Static IP
```bash
# Set cloud-init
qm set 200 --ide2 local-lvm:cloudinit

# Configure static network
qm set 200 --ipconfig0 ip=10.10.20.10/24,gw=10.10.20.1
qm set 200 --nameserver 8.8.8.8
qm set 200 --ciuser debian
qm set 200 --cipassword <your-password>
qm set 200 --sshkeys ~/.ssh/authorized_keys
```

### Step 3.3: Start and Verify Management VM
```bash
# Start VM
qm start 200

# Wait for boot, then SSH via OPNsense
ssh root@10.10.10.1  # First to OPNsense
ssh debian@10.10.20.10  # Then to Management VM
```

## Phase 4: Install Services on Management VM

### Step 4.1: Connect to Management VM
```bash
# From OPNsense or Proxmox
ssh debian@10.10.20.10
sudo -i
```

### Step 4.2: Run Bootstrap Script
```bash
# Clone repository
apt-get update && apt-get install -y git
git clone https://github.com/Rasped/privatebox.git /opt/privatebox
cd /opt/privatebox

# Modify bootstrap for VLAN 20 environment
export MANAGEMENT_IP="10.10.20.10"
export BIND_IP="10.10.20.10"  # Force binding to this IP

# Run Phase 3 only (services installation)
./bootstrap/phase3.sh
```

### Step 4.3: Verify Services
```bash
# Check Podman services
systemctl status podman-portainer
systemctl status podman-semaphore

# Test connectivity
curl -I http://10.10.20.10:9000  # Portainer
curl -I http://10.10.20.10:3000  # Semaphore

# Check DNS will work when AdGuard is deployed
nc -zv 10.10.20.10 53
```

## Phase 5: Deploy AdGuard

### Step 5.1: Access Semaphore
From a machine on the trusted network:
1. Browse to http://10.10.20.10:3000
2. Login with credentials from `/etc/privatebox/config.env`

### Step 5.2: Run AdGuard Deployment
1. Navigate to Templates
2. Run "Deploy AdGuard Home" template
3. Verify deployment completes

### Step 5.3: Configure AdGuard
1. Browse to http://10.10.20.10:3080
2. Complete initial setup
3. Configure upstream DNS servers
4. Add local domain records as needed

## Phase 6: Migrate Proxmox Management

### Step 6.1: Add VLAN 20 Interface to Proxmox
```bash
# Edit network configuration
nano /etc/network/interfaces

# Add VLAN 20 interface
auto vmbr1.20
iface vmbr1.20 inet static
    address 10.10.20.30/24
    gateway 10.10.20.1

# Apply changes
systemctl restart networking
```

### Step 6.2: Test New Interface
```bash
# From Proxmox
ping 10.10.20.1  # OPNsense
ping 10.10.20.10  # Management VM

# Test web UI access
# Browse to https://10.10.20.30:8006
```

### Step 6.3: Remove External Access
```bash
# Edit network configuration
nano /etc/network/interfaces

# Comment out or remove vmbr0 IP configuration
# auto vmbr0
# iface vmbr0 inet static
#     address 192.168.1.10/24
#     gateway 192.168.1.1

# Apply changes
systemctl restart networking
```

## Phase 7: Final Verification

### Step 7.1: Network Connectivity Tests
From OPNsense console:
```bash
# Test all critical services
ping 10.10.20.10  # Management VM
ping 10.10.20.30  # Proxmox
curl http://10.10.20.10:3000/api/ping  # Semaphore
dig @10.10.20.10 google.com  # AdGuard DNS
```

### Step 7.2: Service Health Checks
From Management VM:
```bash
# Check all services running
podman ps

# Check service logs
podman logs portainer
podman logs semaphore
podman logs adguard
```

### Step 7.3: Update Semaphore Inventories
```bash
# Login to Semaphore API
curl -c /tmp/cookies.txt -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth":"admin","password":"<password>"}' \
  http://10.10.20.10:3000/api/auth/login

# Update inventory IPs from 192.168.x.x to 10.10.20.x
# Via UI or API calls
```

## Rollback Procedures

### If OPNsense Fails
1. Power off OPNsense VM
2. Reconfigure Proxmox with original IP on vmbr0
3. Direct connect VMs to vmbr0
4. Troubleshoot OPNsense offline

### If Management VM Fails
1. Access via OPNsense SSH jump
2. Check cloud-init logs: `/var/log/cloud-init.log`
3. Verify network config: `ip addr show`
4. Restart services: `systemctl restart podman-*`

### If Services Don't Bind Correctly
1. Check bind IP in Quadlet files: `/etc/containers/systemd/`
2. Ensure `BIND_IP=10.10.20.10` is set
3. Restart Podman services
4. Check firewall isn't blocking ports

## Success Criteria

✅ OPNsense routing all VLANs  
✅ Management VM accessible on 10.10.20.10  
✅ All services bound to 10.10.20.10  
✅ AdGuard serving DNS on port 53  
✅ Proxmox accessible on 10.10.20.30  
✅ No external access except through OPNsense WAN  
✅ Inter-VLAN communication follows security rules  

## Next Steps

After successful implementation:

1. **Configure Backups**
   - VM snapshots in Proxmox
   - Configuration exports from OPNsense
   - Podman volume backups

2. **Add Monitoring**
   - Deploy Uptime Kuma on Management VM
   - Configure alerts for service failures

3. **Setup Remote Access**
   - Configure WireGuard VPN on OPNsense
   - Or setup jump host access

4. **Deploy Additional Services**
   - Use Semaphore templates
   - Follow same pattern: deploy to Management VM
   - Bind to 10.10.20.10 on different ports

## Troubleshooting Quick Reference

| Issue | Check | Solution |
|-------|-------|----------|
| Can't reach Management VM | VLAN tagging | Ensure `tag=20` on VM network |
| Services not accessible | Binding IP | Check services bound to 10.10.20.10 |
| No internet from VMs | OPNsense WAN | Verify WAN has DHCP lease |
| DNS not working | AdGuard status | Check AdGuard running on port 53 |
| Can't SSH to OPNsense | Interface | Use LAN IP 10.10.20.1 |
| Proxmox not accessible | VLAN interface | Check vmbr1.20 configuration |