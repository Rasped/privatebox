# PrivateBox Go-Live Process

## Overview

This document describes how to transition PrivateBox from a test/staging environment into production as your primary firewall.

## Current State (After Bootstrap)

After running the quickstart/bootstrap, you have:

```
ISP Modem → Your Existing Router (192.168.1.0/24)
                ↓
            Proxmox Host (192.168.1.166)
                ↓ (vmbr0, vmbr1)
            OPNsense VM + Management VM
```

- **Proxmox**: Still on your existing network (e.g., 192.168.1.166)
- **OPNsense WAN**: Gets DHCP from your existing router
- **Internal networks**: Services VLAN (10.10.20.0/24), Trusted LAN (10.10.10.0/24) working internally
- **Proxmox also has**: 10.10.20.20 on vmbr1.20 but no gateway configured

**This is safe for testing** - your existing network still works, PrivateBox is isolated.

## Target State (After Go-Live)

```
ISP Modem (Bridge Mode) → OPNsense WAN (vtnet0)
                              ↓
                         OPNsense Firewall/Router
                              ↓
            ┌─────────────────┴─────────────────┐
            │                                   │
      Services VLAN                        Trusted LAN
      (10.10.20.0/24)                     (10.10.10.0/24)
            │                                   │
      Proxmox: 10.10.20.20              WiFi AP, Clients
      Management VM: 10.10.20.10
      AdGuard, Portainer, etc.
```

- **Proxmox**: Inside on 10.10.20.20, uses OPNsense as gateway
- **OPNsense WAN**: Directly connected to ISP modem
- **All traffic**: Flows through OPNsense firewall
- **DNS**: AdGuard at 10.10.20.10

## Prerequisites

Before going live, ensure:

1. **Physical Setup Ready**
   - [ ] ISP modem configured in bridge mode (not router mode)
   - [ ] OPNsense WAN port (vtnet0/first NIC) will connect to ISP modem
   - [ ] OPNsense LAN port (vtnet1/second NIC) connected to your network switch
   - [ ] WiFi access point connected to switch (will be on LAN VLAN)

2. **PrivateBox Deployed and Tested**
   - [ ] Bootstrap completed successfully
   - [ ] Can access services (Portainer, Semaphore, AdGuard) via .lan domains
   - [ ] AdGuard DNS working (test: `dig @10.10.20.10 google.com`)
   - [ ] OPNsense accessible at 10.10.20.1

3. **Backup Access**
   - [ ] Physical console access to Proxmox host (VGA/HDMI + keyboard)
   - [ ] Alternative internet access (phone hotspot) in case something breaks

## Go-Live Steps

### Step 1: Run the Go-Live Playbook

**⚠️ IMPORTANT**: Run this from Proxmox **console**, NOT via SSH!

SSH access will break during network reconfiguration.

```bash
# Access Proxmox console (physical monitor/keyboard or Proxmox web console)
cd /root/privatebox
ansible-playbook ansible/playbooks/infrastructure/proxmox-go-live.yml
```

**What this does:**
1. Pre-flight checks (OPNsense reachable, AdGuard working)
2. Backs up current network configuration to `/root/privatebox-network-backup/`
3. Creates rollback script at `/root/privatebox-network-rollback.sh`
4. Adds gateway (10.10.20.1) to vmbr1.20
5. Updates DNS to AdGuard (10.10.20.10)
6. Restarts networking
7. Verifies connectivity through OPNsense

**Timeline**: 30-60 seconds for network restart and verification.

### Step 2: Physical Cabling

Once the playbook succeeds:

1. **Disconnect current setup**:
   - Unplug Proxmox from existing router/switch

2. **Connect to OPNsense**:
   - Connect Proxmox to the same switch as OPNsense LAN port
   - OPNsense should already be connected:
     - WAN port → ISP modem (bridge mode)
     - LAN port → Switch → Proxmox + WiFi AP

3. **Verify connectivity**:
   - From Proxmox console: `ping 10.10.20.1` (OPNsense)
   - From Proxmox console: `ping 8.8.8.8` (internet)
   - From Proxmox console: `curl https://www.google.com`

### Step 3: Test Client Connectivity

1. **Connect a device to WiFi/LAN**
   - Should get IP from OPNsense DHCP (10.10.10.x range)
   - Should get DNS server: 10.10.20.10 (AdGuard)

2. **Test connectivity**:
   - `ping 8.8.8.8` - internet reachable
   - `nslookup google.com` - DNS working
   - Browse to `https://privatebox.lan` - dashboard accessible
   - Browse to `https://adguard.lan` - AdGuard web UI

3. **Test DNS filtering**:
   - Visit a site on AdGuard blocklist
   - Should be blocked
   - Check AdGuard dashboard for query logs

## Rollback Procedure

If something goes wrong, you have two options:

### Option 1: Automated Rollback

From Proxmox console:

```bash
/root/privatebox-network-rollback.sh
```

This restores the previous network configuration.

### Option 2: Manual Rollback

1. Boot Proxmox to console
2. Restore network config:
   ```bash
   cp /root/privatebox-network-backup/interfaces.backup.* /etc/network/interfaces
   cp /root/privatebox-network-backup/resolv.conf.backup.* /etc/resolv.conf
   ifreload -a
   ```
3. Reconnect Proxmox to old network
4. Verify connectivity

## Post-Go-Live Configuration

After successfully going live:

### Update Proxmox Web Access

Proxmox web UI now accessible at:
- **Old URL** (may not work): `https://192.168.1.166:8006`
- **New URL**: `https://10.10.20.20:8006`
- **Or via domain** (configure DNS): `https://proxmox.lan:8006`

### Configure OPNsense for Production

1. **Change default passwords**:
   - OPNsense: Currently `on5laught-rum0r-pre4CHy-4TTribute-ozOn3`
   - Change via web UI at `https://opnsense.lan`

2. **Verify firewall rules**:
   - Check Rules > Floating, WAN, LAN tabs
   - Ensure appropriate blocking for WAN

3. **Configure ISP settings** (if needed):
   - Some ISPs require specific WAN settings
   - PPPoE credentials, VLAN tagging, etc.
   - Configure in Interfaces > WAN

### Update DNS Records (Optional)

If using custom domain (deSEC.io):
- Update A records to point to your new WAN IP
- Caddy will handle Let's Encrypt certificates via DNS-01

### Set Up Remote Access (Optional)

Use Tailscale/Headscale for secure remote access:
- Already deployed as part of bootstrap
- Access Headplane at `https://headplane.lan/admin`
- Create user, register devices
- Connect via Tailscale client from phone/laptop

## Troubleshooting

### Proxmox loses connectivity after playbook

**Symptoms**: Can't ping gateway, no internet

**Fix**:
1. Access console
2. Check: `ip addr show vmbr1.20` - should have 10.10.20.20/24
3. Check: `ip route show` - should have default via 10.10.20.1
4. Check: `ping 10.10.20.1` - should respond
5. If not, run rollback script

### Clients can't get DHCP

**Symptoms**: Devices connected but no IP address

**Fix**:
1. Check OPNsense DHCP service: Services > DHCPv4
2. Verify LAN interface has DHCP enabled
3. Check OPNsense logs: System > Log Files > DHCP

### DNS not resolving

**Symptoms**: Can ping 8.8.8.8 but not google.com

**Fix**:
1. Check if AdGuard is running: `ssh debian@10.10.20.10 'podman ps'`
2. Check if clients received correct DNS (should be 10.10.20.10)
3. Test AdGuard directly: `dig @10.10.20.10 google.com`
4. Check AdGuard logs at `https://adguard.lan`

### Can't access services via .lan domains

**Symptoms**: Can access by IP but not privatebox.lan

**Fix**:
1. Check AdGuard DNS rewrites: AdGuard > Filters > DNS rewrites
2. Should have entries for *.lan → 10.10.20.10
3. Check Caddy is running: `ssh debian@10.10.20.10 'podman ps | grep caddy'`
4. Test resolution: `nslookup privatebox.lan 10.10.20.10`

### ISP connection not working

**Symptoms**: OPNsense WAN has no IP or internet

**Fix**:
1. Verify ISP modem in bridge mode
2. Check OPNsense WAN: Interfaces > Overview
3. Check WAN should show public IP
4. Try reboot modem and OPNsense
5. Check ISP requirements (PPPoE, VLAN tags, etc.)

## Safety Notes

1. **Console Access is Critical**: Always have physical access during go-live
2. **ISP Modem Settings**: Verify bridge mode before starting
3. **Backup Configuration**: Keep old router handy as emergency backup
4. **Test Incrementally**: Don't do this during critical work hours
5. **Document Changes**: Note any custom ISP settings needed

## Success Checklist

After go-live, verify:

- [ ] Proxmox accessible at https://10.10.20.20:8006
- [ ] OPNsense accessible at https://opnsense.lan or https://10.10.20.1
- [ ] WiFi clients get IP addresses (10.10.10.x)
- [ ] Clients can browse internet
- [ ] DNS filtering working (blocked domains don't load)
- [ ] Services accessible via .lan domains
- [ ] Portainer at https://portainer.lan
- [ ] Semaphore at https://semaphore.lan
- [ ] AdGuard at https://adguard.lan
- [ ] Dashboard at https://privatebox.lan

## Next Steps

Once stable:
1. Update passwords for all services
2. Configure DNS filtering lists in AdGuard
3. Set up Tailscale for remote access
4. Configure OPNsense firewall rules per your needs
5. Set up external domain with Let's Encrypt (optional)
6. Configure automated backups
