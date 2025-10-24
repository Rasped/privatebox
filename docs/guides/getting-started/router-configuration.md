# Router configuration guide

This guide provides specific instructions for configuring common router brands to work with PrivateBox.

## General approach

You have two options for any router:

**Option 1: Disable DHCP server** (works with all routers)
- Keeps router's Wi-Fi working
- Router continues handling wireless connections
- PrivateBox handles IP addresses

**Option 2: Enable access point mode** (if available - preferred)
- Automatically disables DHCP
- Cleaner configuration
- Router becomes a simple Wi-Fi access point

## Common router brands

### Asus routers

**To disable DHCP:**
1. Visit http://router.asus.com or http://192.168.1.1
2. Go to **LAN** → **DHCP Server**
3. Set **Enable DHCP Server** to **No**
4. Click **Apply**

**To enable AP mode (preferred):**
1. Go to **Administration** → **Operation Mode**
2. Select **Access Point Mode**
3. Click **Save** and wait for reboot

### TP-Link routers

**To disable DHCP:**
1. Visit http://tplinkwifi.net or http://192.168.0.1
2. Go to **DHCP** → **DHCP Settings**
3. Disable **DHCP Server**
4. Click **Save**

**To enable AP mode (preferred):**
1. Go to **Advanced** → **Operation Mode**
2. Select **Access Point**
3. Click **Save** and wait for reboot

### Netgear routers

**To disable DHCP:**
1. Visit http://routerlogin.net or http://192.168.1.1
2. Go to **Advanced** → **Setup** → **LAN Setup**
3. Uncheck **Use Router as DHCP Server**
4. Click **Apply**

**To enable AP mode (preferred):**
1. Go to **Advanced** → **Advanced Setup** → **Router/AP Mode**
2. Select **AP Mode**
3. Click **Apply** and wait for reboot

### Linksys routers

**To disable DHCP:**
1. Visit http://myrouter.local or http://192.168.1.1
2. Go to **Connectivity** → **Local Network**
3. Turn off **DHCP Server**
4. Click **Apply**

### D-Link routers

**To disable DHCP:**
1. Visit http://192.168.0.1
2. Go to **Setup** → **Network Settings**
3. Uncheck **Enable DHCP Server**
4. Click **Save Settings**

### AVM Fritz!Box (common in EU)

**To enable guest access mode (AP mode):**
1. Visit http://fritz.box
2. Go to **Internet** → **Account Information**
3. Click **Change connection settings**
4. Select **Connected to an external router or modem**
5. Follow the wizard

### Ubiquiti routers

Ubiquiti devices are typically configured for advanced use. If you have a UniFi setup, PrivateBox can integrate as the gateway while keeping UniFi for switching and Wi-Fi.

Consult Ubiquiti documentation or contact support for specific configuration.

## Mesh systems

Google WiFi, eero, Nest WiFi, and similar mesh systems need different configuration.

### Option 1: Replace mesh system (recommended)

Use PrivateBox as your router and connect a Wi-Fi access point or your old router in AP mode to PrivateBox.

Pros:
- Full PrivateBox protection
- Simpler network topology

Cons:
- Mesh system's advanced features disabled
- May need to add separate Wi-Fi access points

### Option 2: Keep mesh as router (not recommended)

Place PrivateBox behind your mesh system.

Cons:
- Defeats PrivateBox's firewall and filtering
- Double NAT issues
- Limited protection

## After configuration

After disabling DHCP or enabling AP mode:

1. Your router may reboot (1-2 minutes)
2. Your devices may need to reconnect to Wi-Fi
3. Return to the [Getting Started Guide](./getting-started.md) to complete setup

## Still stuck?

- Try the [Finding Router Settings](./finding-router-settings.md) guide
- Search online: "[your router model] disable DHCP" or "[your router model] AP mode"
- See the [Troubleshooting Guide](./troubleshooting-guide.md)
