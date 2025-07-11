# AdGuard Home Deployment Guide

## Overview
This guide explains the complete hands-off deployment process for AdGuard Home using PrivateBox's Ansible automation with Semaphore UI.

## What's Been Implemented

### 1. Semaphore Integration ✅
The AdGuard playbook now includes metadata for automatic template generation:
- **Boolean prompt**: Deployment confirmation
- **Integer prompt**: Custom web port (1024-65535)
- Templates auto-created when running "Generate Templates" in Semaphore

### 2. DNS Conflict Resolution ✅
Automatic handling of systemd-resolved on Ubuntu:
- Detects if systemd-resolved is using port 53
- Gracefully stops and disables the service
- Creates temporary DNS configuration
- Preserves network connectivity during transition

### 3. Firewall Configuration ✅
Automatic UFW firewall rules:
- AdGuard web interface port
- DNS TCP/UDP ports
- DNS-over-TLS support (if configured)
- Graceful handling if UFW is not installed

### 4. Enhanced Health Checks ✅
Comprehensive DNS verification:
- Waits for DNS service to stabilize
- Tests actual DNS resolution
- Retries with different domains
- Updates host DNS only if working

### 5. Host DNS Management ✅
Intelligent DNS configuration:
- Updates /etc/resolv.conf to use AdGuard
- Includes fallback DNS servers (1.1.1.1, 9.9.9.9)
- Protects configuration from being overwritten
- Shows status in deployment summary

## Deployment Workflow

### Step 1: Bootstrap Setup (One-Time)
```bash
# On Proxmox host
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```
This automatically:
- Creates Ubuntu VM
- Installs Portainer and Semaphore
- Sets up template synchronization infrastructure
- Runs initial template generation

### Step 2: Access Semaphore UI
```bash
# Get VM IP from bootstrap output
# Access Semaphore at: http://<VM-IP>:3000
# Login: admin / <password-from-bootstrap>
```

### Step 3: Run Template Synchronization
1. Navigate to "Task Templates" in Semaphore
2. Find "Generate Templates" task
3. Click "Run" to sync playbooks
4. Verify "Deploy: adguard" template is created

### Step 4: Deploy AdGuard Home
1. Click on "Deploy: adguard" template
2. Fill in survey:
   - **Deploy AdGuard Home?**: Yes
   - **Web UI port**: 8080 (or custom)
3. Click "Run"

### Step 5: Monitor Deployment
The playbook will:
1. ✓ Check system requirements
2. ✓ Install Podman if needed
3. ✓ Handle systemd-resolved conflicts
4. ✓ Check port availability
5. ✓ Deploy AdGuard container
6. ✓ Configure firewall rules
7. ✓ Verify DNS functionality
8. ✓ Update host DNS configuration

### Step 6: Complete Web Setup
After deployment:
1. Visit: `http://<VM-IP>:8080` (or custom port)
2. Complete AdGuard setup wizard
3. Set admin username/password
4. Configure blocklists

## What Happens Behind the Scenes

### DNS Transition Process
```
1. systemd-resolved running on port 53
   ↓
2. Playbook stops systemd-resolved
   ↓
3. Temporary DNS servers configured (1.1.1.1, 8.8.8.8)
   ↓
4. AdGuard container starts
   ↓
5. DNS functionality verified
   ↓
6. Host DNS updated to use AdGuard (with fallbacks)
```

### Port Management
- **Default Web Port**: 8080 (avoids conflicts with common services)
- **DNS Port**: 53 (standard, after clearing conflicts)
- **Development Override**: Can use 8081 to avoid conflicts

### Health Verification
1. Container health check via HTTP
2. DNS port availability check
3. Actual DNS resolution test
4. Retry logic for stability

## Troubleshooting

### DNS Not Working
```bash
# Check AdGuard container
sudo podman ps | grep adguard
sudo podman logs adguard-home

# Test DNS directly
dig @<VM-IP> google.com

# Check systemd service
sudo systemctl status adguard-container
```

### Port Conflicts
```bash
# Check what's using ports
sudo ss -tlnp | grep -E ':53|:8080'

# Restart with different port
# Re-run playbook with custom_web_port
```

### Firewall Issues
```bash
# Check UFW status
sudo ufw status

# Manually add rules if needed
sudo ufw allow 8080/tcp comment "AdGuard Web"
sudo ufw allow 53/tcp comment "DNS TCP"
sudo ufw allow 53/udp comment "DNS UDP"
```

### DNS Resolution on Host
```bash
# Check current DNS
cat /etc/resolv.conf

# Test resolution
nslookup google.com
dig google.com
```

## Security Considerations

1. **Default Credentials**: Change immediately after setup
2. **Firewall Rules**: Only required ports are opened
3. **DNS Fallback**: Prevents total DNS failure
4. **Container Isolation**: Podman provides security boundaries
5. **No Root**: Container runs without root privileges

## Customization Options

### Variables You Can Override
- `adguard_web_port`: Web interface port (default: 8080)
- `adguard_dns_port`: DNS service port (default: 53)
- `adguard_memory_limit`: Memory limit (default: 512M)
- `adguard_cpu_quota`: CPU limit (default: 50%)

### Advanced Configuration
Edit `/opt/privatebox/config/adguard/AdGuardHome.yaml` after initial setup for:
- Custom blocklists
- DNS upstream servers
- DHCP settings
- TLS configuration

## Maintenance

### Backup
```bash
# Backup AdGuard data
sudo tar -czf adguard-backup.tar.gz \
  /opt/privatebox/data/adguard \
  /opt/privatebox/config/adguard
```

### Update Container
```bash
# Pull latest image
sudo podman pull adguard/adguardhome:latest

# Restart service
sudo systemctl restart adguard-container
```

### View Logs
```bash
# Container logs
sudo podman logs -f adguard-home

# Service logs
sudo journalctl -u adguard-container -f
```

## Integration with Other Services

### With Pi-hole
- Run on different port (Pi-hole: 8081)
- Use as upstream DNS for each other

### With Unbound
- AdGuard forwards to Unbound (port 5335)
- Unbound provides recursive DNS

### With WireGuard
- AdGuard as DNS for VPN clients
- Provides ad-blocking over VPN

## Summary

The AdGuard Home deployment is now truly hands-off:
1. ✅ Automatic Semaphore template creation
2. ✅ Intelligent DNS conflict resolution
3. ✅ Automated firewall configuration
4. ✅ Comprehensive health verification
5. ✅ Host DNS auto-configuration

Users simply click "Run" in Semaphore UI and get a working AdGuard installation with proper DNS configuration and fallback protection.