# PrivateBox Quick Start Guide

**Welcome to PrivateBox.** This guide will get you connected in minutes.

## What's in the box
- PrivateBox appliance
- Power adapter
- Quick Start Guide (this document)

## Step 1: Physical setup (2 minutes)

1. **Connect WAN port** (marked WAN or Port 1) to your modem/ISP connection
2. **Connect LAN port** (marked LAN or Port 2) to your network switch or directly to your computer
3. **Plug in power** and press the power button
4. **Wait 2 minutes** for the system to boot

## Step 2: First login (3 minutes)

1. **Connect to the network** plugged into the LAN port
2. **Open your browser** and navigate to: `https://privatebox.lan`
3. **You'll see the Homer Dashboard** - your central hub for all services

### Default credentials

Your unique credentials are printed on the label inside this box:

- **Username:** `admin`
- **Password:** `[printed on label]`

Important: Change this password immediately after first login.

## Step 3: Access core services

From the Homer Dashboard, you can access:

- **OPNsense** (`https://opnsense.lan`) - Firewall and router configuration
- **AdGuard Home** (`https://adguard.lan`) - DNS filtering and ad-blocking
- **Portainer** (`https://portainer.lan`) - Container management
- **Semaphore** (`https://semaphore.lan`) - Automation and updates

**First-time Portainer setup:** You have 5 minutes after first boot to create your Portainer admin account. Navigate to `https://portainer.lan` immediately.

## Step 4: Basic configuration

For detailed setup instructions, visit:

**https://privatebox.com/docs/getting-started**

This includes:
- Changing default passwords
- Configuring your WAN connection
- Setting up VLANs for network segmentation
- Configuring DNS filtering
- Setting up remote VPN access

## Need help?

- **Documentation:** https://privatebox.com/docs
- **Community Support:** r/homelab, r/selfhosted
- **Direct Support:** support@subrosa.dev (for hardware/warranty issues)
- **Health Check:** Run the diagnostic script from Semaphore to verify all services

## Quick tips

- **Backups:** Configure automated backups in Semaphore
- **Updates:** The system will notify you of available updates. You control when to apply them.
- **Network Planning:** Consider setting up VLANs to isolate IoT devices from your main network
- **VPN Access:** Configure Headscale for secure remote access to your network

---

**Assembled in Denmark** | **Open Source** | **No Subscriptions, Ever**

support@subrosa.dev | https://privatebox.com
