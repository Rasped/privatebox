# OPNsense Template Documentation

## Template Details
- **Template ID**: 100
- **Name**: opnsense-prod
- **Version**: OPNsense 25.7 (amd64)
- **Created**: August 22, 2025
- **Base Disk**: base-100-disk-0 (16GB)

## Hardware Configuration
- **CPU**: 2 cores (host type)
- **RAM**: 4096 MB
- **Network**:
  - net0: virtio on vmbr0 (WAN)
  - net1: virtio on vmbr1 (LAN)
- **Boot**: Auto-start enabled (onboot=1)

## Network Configuration
- **WAN (vtnet0)**: DHCP client
- **LAN (vtnet1)**: 10.10.10.1/24
- **SSH Access**: Enabled on LAN interface only
- **Default Credentials**: root/opnsense

## Firewall Rules
- Default LAN to any (IPv4 and IPv6)
- SSH allowed on LAN interface
- Anti-lockout rule active

## Config Backup
- Location: `ansible/files/opnsense/config-vm100-backup.xml`
- MD5: fbbc02221a7617e01fa2bd5c96e02fbb
- Size: 62,680 bytes

## Backup Details
- **Filename**: vzdump-qemu-101-opnsense.vma.zst
- **Size**: 771MB (compressed with zstd)
- **MD5**: e7cf310cd3386eed54d1ff43c6c98837
- **Original Size**: 16GB allocated, 2.83GB used (82% sparse)
- **Compression**: ~73% reduction from actual data
- **Note**: Filename must follow `vzdump-qemu-*` pattern for Proxmox compatibility

## Deployment Usage

### Method 1: From Backup File (Recommended)
```bash
# Download the backup file from GitHub releases
wget https://github.com/Rasped/privatebox/releases/download/v1.0.0-opnsense/vzdump-qemu-101-opnsense.vma.zst

# Restore to new VM (e.g., VMID 101)
qmrestore vzdump-qemu-101-opnsense.vma.zst 101

# Start the VM
qm start 101
```

### Method 2: Clone from Template (if template exists on host)
```bash
# From Proxmox host
qm clone 100 <NEW_VMID> --name <VM_NAME>
qm set <NEW_VMID> --onboot 1
qm start <NEW_VMID>
```

### Apply Custom Configuration
```bash
# After VM starts, apply saved config
scp config.xml root@10.10.10.1:/conf/config.xml
ssh root@10.10.10.1 "configctl firmware restart"
```

## Notes
- Template uses minimal configuration suitable for most deployments
- WAN will obtain IP via DHCP
- LAN is pre-configured with 10.10.10.1/24
- No VLANs configured in base template
- No additional packages installed
- SSH is enabled on both WAN and LAN interfaces with root/opnsense credentials
- Firewall blocks WAN SSH access by default (accessible from local network only)