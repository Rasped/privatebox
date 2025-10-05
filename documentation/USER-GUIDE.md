# PrivateBox User Guide

## Understanding Certificate Warnings

When you first access PrivateBox services (Portainer, Semaphore, AdGuard, Headscale), your browser will display a security warning:

> ⚠️ **"Your connection is not private"**

**This is normal and expected.** Here's why:

### Why Self-Signed Certificates?

PrivateBox uses self-signed HTTPS certificates for security without requiring:

- ❌ **Domain purchase** - No $15/year recurring cost
- ❌ **External DNS services** - Avoids privacy concerns from third-party DNS providers
- ❌ **Internet connectivity** - Certificate renewal doesn't require online access
- ❌ **Vendor dependencies** - Works completely offline during network recovery

### What to Expect

**First visit to each service:**
1. Browser shows: *"Your connection is not private"* or *"Warning: Potential Security Risk Ahead"*
2. Click **"Advanced"** (Chrome/Edge) or **"Advanced..."** (Firefox)
3. Click **"Proceed to 10.10.20.10"** (Chrome/Edge) or **"Accept the Risk and Continue"** (Firefox)
4. Your browser remembers this choice
5. All future visits work normally with HTTPS protection

**After accepting the certificate:**
- ✅ All traffic is encrypted with TLS 1.3
- ✅ Protection from passive network eavesdropping
- ✅ Browser address bar shows 🔒 (padlock icon)
- ✅ No more warnings on subsequent visits

### Industry Standard Approach

This is the **same approach** used by professional network appliances:

- **UniFi Dream Machine** (Ubiquiti) - Self-signed HTTPS
- **Firewalla Gold** - Self-signed HTTPS
- **Synology NAS** - Self-signed HTTPS
- **pfSense / OPNsense** - Self-signed HTTPS
- **Enterprise routers** (Cisco, Juniper) - Self-signed HTTPS

All of these products show the same browser warnings on first access.

### Security Considerations

**Self-signed certificates protect against:**
- ✅ Passive network sniffing (traffic encryption)
- ✅ Man-in-the-middle attacks on local network (if you verify fingerprint)
- ✅ Credential theft over WiFi

**Self-signed certificates do NOT protect against:**
- ❌ Active man-in-the-middle attacks (without fingerprint verification)
- ❌ Compromised local network equipment
- ❌ DNS hijacking to wrong IP address

**Why this is acceptable for PrivateBox:**
- You're accessing services on your **own local network** (10.10.20.x addresses)
- These services are **not exposed to the internet**
- If an attacker controls your local network, they already have physical/network access
- HTTPS prevents passive WiFi sniffing of your admin passwords

### For Advanced Users: Let's Encrypt (Optional)

If you own a domain and want browser-trusted certificates:

1. **Requirements:**
   - Registered domain name (e.g., `example.com`)
   - Internet connectivity for initial setup and 90-day renewals
   - DNS provider with API support (Cloudflare, Route53, etc.)

2. **Benefits:**
   - No browser warnings
   - Automatic certificate renewal every 90 days
   - Chain of trust to public Certificate Authority

3. **Trade-offs:**
   - Requires domain ownership and annual renewal ($10-15/year)
   - Requires internet access for certificate issuance/renewal
   - Creates dependency on Let's Encrypt service availability
   - Recovery scenarios become more complex

**Setup guide:** See `documentation/advanced/letsencrypt-setup.md` (coming soon)

## Quick Reference

### Dashboard Access
- **URL:** http://10.10.20.10:8081
- **Purpose:** Central hub with links to all services
- **No login required** (HTTP-only, just provides navigation)

### Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **Portainer** | https://10.10.20.10:1443 | Manage containers |
| **Semaphore** | https://10.10.20.10:2443 | Deploy services via Ansible |
| **AdGuard Home** | https://10.10.20.10:3443 | Configure DNS filtering |
| **Headscale** | https://10.10.20.10:4443 | VPN control server API |
| **OPNsense** | https://10.10.20.1 | Firewall management |

### Default Credentials

All services use the same admin credentials (printed on device label):

- **Username:** admin
- **Password:** *(see device label or `/etc/privatebox/config.env` on Management VM)*

**⚠️ Change the default password immediately after first login!**

## Network Architecture

PrivateBox creates a secure network segment:

- **WAN Interface:** Connects to your existing router
- **LAN Interface:** Creates new 10.10.20.0/24 network with VLANs:
  - `10.10.20.0/26` - Services VLAN (management services)
  - `10.10.20.64/26` - Clients VLAN (your devices)
  - `10.10.20.128/26` - IoT VLAN (smart home devices)
  - `10.10.20.192/26` - Guest VLAN (visitor WiFi)

All devices get DNS filtering and firewall protection automatically.

**For detailed network architecture:** See `documentation/network-architecture/vlan-design.md`

## Troubleshooting

### Cannot Access Dashboard (http://10.10.20.10:8081)

**Check your IP address:**
```bash
# macOS/Linux:
ifconfig | grep "inet "

# Windows:
ipconfig
```

You must be on the `10.10.20.x` network. If not:
1. Ensure your device is connected to PrivateBox LAN
2. Check if you received IP via DHCP
3. Manually set IP to `10.10.20.65` (Clients VLAN)

### Cannot Accept Certificate on Mobile

Some mobile browsers (especially iOS Safari) don't show "Advanced" button:

**Solution for iOS:**
1. Tap anywhere on the warning page
2. Type: `thisisunsafe` (no text field will appear, just type it)
3. Page will reload and accept the certificate

**Solution for Android:**
1. Tap "Advanced" or "Details"
2. Tap "Visit this unsafe site" or "Continue anyway"

### Service Shows "Connection Refused"

**Check service status via SSH:**
```bash
ssh debian@10.10.20.10
sudo systemctl status portainer semaphore adguard headscale
```

**Restart failed service:**
```bash
sudo systemctl restart <service-name>
```

### Forgot Admin Password

**Reset from Management VM:**
```bash
ssh debian@10.10.20.10
cat /etc/privatebox/config.env | grep SERVICES_PASSWORD
```

## Support

- **Documentation:** https://docs.privatebox.io
- **Community Forum:** https://community.privatebox.io
- **Email Support:** support@subrosa.dk
- **GitHub Issues:** https://github.com/Rasped/privatebox/issues

---

**PrivateBox** - Open source privacy appliance
© 2025 SubRosa ApS, Denmark
