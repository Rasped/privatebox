# Local Package Mirror Setup for PrivateBox

This guide explains how to set up a local package cache to speed up PrivateBox installations and avoid rate limiting from Ubuntu's servers.

## Overview

When installing multiple PrivateBox VMs, each installation downloads the same packages from Ubuntu's servers. This can:
- Be slow due to internet bandwidth
- Trigger rate limiting after multiple installations
- Waste bandwidth downloading the same files repeatedly

A local package cache solves these issues by storing packages after the first download and serving them locally for subsequent installations.

## Setting Up Apt-Cacher-NG

Apt-Cacher-NG is a caching proxy specifically designed for Debian/Ubuntu packages. It automatically caches any package that passes through it.

### 1. Install Apt-Cacher-NG on Your Proxmox Host

```bash
# Update package list
apt update

# Install Apt-Cacher-NG
apt install apt-cacher-ng

# Enable and start the service
systemctl enable apt-cacher-ng
systemctl start apt-cacher-ng

# Verify it's running
systemctl status apt-cacher-ng
```

### 2. Verify the Installation

- The cache proxy runs on port **3142** by default
- Test it by visiting: `http://YOUR-PROXMOX-IP:3142/acng-report.html`
- You should see the Apt-Cacher-NG statistics page

### 3. Configure PrivateBox to Use the Cache

Add the proxy configuration to your PrivateBox config file:

```bash
# Edit the PrivateBox configuration
cd /path/to/privatebox
cp bootstrap/config/privatebox.conf.example bootstrap/config/privatebox.conf

# Add this line to the configuration file:
echo 'APT_PROXY_URL="http://192.168.1.10:3142"' >> bootstrap/config/privatebox.conf
```

Replace `192.168.1.10` with your Proxmox host's IP address.

### 4. Modify the VM Creation Script

Add the following to `bootstrap/scripts/create-ubuntu-vm.sh` in the cloud-init section:

```yaml
# Add this to the write_files section of cloud-init
  - path: /etc/apt/apt.conf.d/00proxy
    permissions: '0644'
    content: |
      Acquire::http::Proxy "http://192.168.1.10:3142";
      Acquire::https::Proxy "DIRECT";
```

Or add it to the runcmd section:

```yaml
runcmd:
  # Configure apt proxy (if available)
  - |
    if [ -n "${APT_PROXY_URL}" ]; then
      echo "Acquire::http::Proxy \"${APT_PROXY_URL}\";" > /etc/apt/apt.conf.d/00proxy
      echo "Acquire::https::Proxy \"DIRECT\";" >> /etc/apt/apt.conf.d/00proxy
    fi
```

## Testing the Setup

1. **First Installation**: Run a PrivateBox installation normally
   - Packages will be downloaded from Ubuntu servers
   - Apt-Cacher-NG will cache them automatically

2. **Check Cache Statistics**:
   ```bash
   # View cache statistics
   curl http://YOUR-PROXMOX-IP:3142/acng-report.html
   
   # Or check the log
   tail -f /var/log/apt-cacher-ng/apt-cacher.log
   ```

3. **Second Installation**: Run another PrivateBox installation
   - Packages will be served from cache (much faster)
   - You'll see "HIT" entries in the apt-cacher.log

## Benefits

- **Speed**: Package downloads from cache are 10-100x faster
- **Bandwidth**: Save internet bandwidth by downloading packages only once
- **Reliability**: No rate limiting issues
- **Automatic**: Works transparently once configured

## Troubleshooting

### VMs Can't Reach the Proxy
- Ensure the VM network can reach the Proxmox host
- Check firewall rules: `ufw allow 3142/tcp`
- Test connectivity: `curl http://192.168.1.10:3142`

### Cache Not Working
- Check logs: `/var/log/apt-cacher-ng/apt-cacher.log`
- Verify proxy setting in VM: `cat /etc/apt/apt.conf.d/00proxy`
- Clear apt cache in VM and retry: `apt clean`

### Disk Space
- Cache location: `/var/cache/apt-cacher-ng/`
- Monitor disk usage: `du -sh /var/cache/apt-cacher-ng/`
- Configure automatic cleanup in `/etc/apt-cacher-ng/acng.conf`:
  ```
  ExThreshold: 30
  ```

## Advanced Configuration (Optional)

### Cache Docker Images
For caching container images, consider adding a Docker registry proxy:
```bash
docker run -d -p 5000:5000 --restart=always --name registry \
  -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
  registry:2
```

### Use Separate Storage
Move cache to a dedicated disk:
```bash
# Stop the service
systemctl stop apt-cacher-ng

# Move cache directory
mv /var/cache/apt-cacher-ng /path/to/larger/disk/
ln -s /path/to/larger/disk/apt-cacher-ng /var/cache/apt-cacher-ng

# Start the service
systemctl start apt-cacher-ng
```

## Summary

Setting up Apt-Cacher-NG takes about 5 minutes and provides immediate benefits for repeated PrivateBox installations. The cache is transparent to the VMs and requires no maintenance once configured.