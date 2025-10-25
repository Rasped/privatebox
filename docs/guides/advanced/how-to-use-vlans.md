# Advanced: How to use VLANs

This guide explains how to use the pre-configured VLANs (Virtual LANs) on your PrivateBox to segment your network. 

---

### Prerequisite: VLAN-capable hardware

To use this feature, you **must** have your own network switch or wireless access point (AP) that is VLAN-capable. PrivateBox creates and manages the secure network segments, but your hardware is responsible for assigning devices to them. This functionality is often found in prosumer or business-grade network equipment.

### Using privatebox without VLAN hardware

If your router or access point doesn't support VLANs, you can still use PrivateBox. All devices will connect to the Trusted network (the default untagged network), and you'll still get:

- Ad blocking via DNS filtering
- Malware and tracker protection
- Secure access to PrivateBox management interfaces

However, without VLAN-capable hardware, you can't:

- Isolate guest devices from your personal devices
- Segment IoT devices into separate security zones
- Block local-only IoT devices from accessing the internet
- Separate cameras for privacy

Your router's "guest network" feature may provide basic wireless isolation, but this doesn't provide the same level of security as true VLAN segmentation.

---

### Compatible hardware

If you want to use VLANs with PrivateBox, you need VLAN-capable network equipment. Here are tested options:

**Budget option - TP-Link Omada:**
- TP-Link EAP225 (around $60) - WiFi 5, good for most homes
- TP-Link EAP610 (around $90) - WiFi 6, better performance
- Supports 16 SSIDs with VLAN tagging
- No subscription or cloud account required

**Premium option - Ubiquiti UniFi:**
- UniFi U6-Lite (around $99) - WiFi 6, compact design
- UniFi U6-Pro (around $159) - WiFi 6, higher performance
- UniFi U6-Enterprise (around $249) - WiFi 6E, maximum performance
- Requires UniFi Network Controller software (free)

**What to look for:**
- "VLAN tagging" or "802.1Q" support
- "Multiple SSID" support (for WiFi)
- "Trunk port" configuration (for switches)

**What to avoid:**
- Consumer routers marketed as "gaming routers"
- Devices that only support "guest networks" (not true VLANs)
- Equipment requiring cloud subscriptions for VLAN features

---

### The concept

Your PrivateBox has a single physical LAN port, but it broadcasts multiple, isolated networks over that one connection. Each of these networks is identified by a unique "VLAN ID" or "Tag".

Your VLAN-capable switch or AP can read these tags. You can configure your hardware to, for example, assign a specific port on your switch to VLAN 30, or create a new Wi-Fi network that places any connected device onto VLAN 40.

This allows you to place devices into the correct security zone.

---

### PrivateBox VLAN architecture

This table contains the information you will need to configure your own hardware.

| VLAN ID | Network       | Purpose                                      | DHCP Pool         | Notes                            |
|:--------|:--------------|:---------------------------------------------|:------------------|:---------------------------------|
| Untagged| 10.10.10.0/24 | **Trusted** - Family devices & trusted computers | 10.10.10.100-200  | No VLAN tag required             |
| 20      | 10.10.20.0/24 | **Services** - PrivateBox infrastructure         | None (all static) | Management VM, Proxmox, OPNsense; do not assign to client ports |
| 30      | 10.10.30.0/24 | **Guest** - Visitor devices                      | 10.10.30.100-120  | Internet-only access             |
| 40      | 10.10.40.0/24 | **IoT Cloud** - Smart devices requiring internet | 10.10.40.100-200  | Smart TVs, voice assistants      |
| 50      | 10.10.50.0/24 | **IoT Local** - Local-only smart devices         | 10.10.50.100-200  | No internet access               |
| 60      | 10.10.60.0/24 | **Cameras Cloud** - Cameras with cloud recording | 10.10.60.100-150  | Ring, Nest, etc.                 |
| 70      | 10.10.70.0/24 | **Cameras Local** - Local-only cameras           | 10.10.70.100-150  | No internet access               |

**Note:** "Untagged" refers to the default network that does not require any VLAN configuration on your hardware. Devices connected to a standard, non-configured port will automatically join the Trusted network. All other VLANs require you to explicitly tag ports or wireless networks with their VLAN ID.

---

### Generic workflow

While the specific steps depend on your hardware, the general process is as follows:

1.  **Connect Hardware:** Connect your VLAN-capable switch or access point to the port on the right (LAN) on your PrivateBox.

2.  **Log in to Your Switch/AP:** Open the management interface for your network hardware.

3.  **Create a New Network/VLAN:** Find the section for creating a new LAN, network, or wireless network (SSID).

4.  **Enter the VLAN ID:** When prompted for a **VLAN ID** or **VLAN Tag**, enter the corresponding number from the table above. For example, to create a guest Wi-Fi network, you would enter `30`.

5.  **Assign the Network:** You can now either assign a specific physical port on your switch to this new VLAN, or, if you are creating a wireless network, save the new Wi-Fi SSID.

6.  **Configure the uplink:** Set the switch port connected to PrivateBox as a tagged trunk that carries VLANs 20–70 and leaves the Trusted network untagged.

Any device connected to that port or that Wi-Fi network will now be automatically placed in the correct security zone managed by your PrivateBox.

---

### Verify your VLAN configuration

After setting up a VLAN, verify it works correctly:

**Step 1: Connect a test device**

Connect a device (phone, laptop, or tablet) to the VLAN you just created.

**Step 2: Check IP address**

Verify the device received an IP address in the correct range:

- Guest (VLAN 30): 10.10.30.100-120
- IoT Cloud (VLAN 40): 10.10.40.100-200
- IoT Local (VLAN 50): 10.10.50.100-200
- Cameras Cloud (VLAN 60): 10.10.60.100-150
- Cameras Local (VLAN 70): 10.10.70.100-150

On most devices, you can find the IP address in network settings or WiFi connection details.

**Step 3: Test internet access**

Open a web browser and visit any website:

- Guest, IoT Cloud, Cameras Cloud: Internet should work
- IoT Local, Cameras Local: Internet should be blocked

**Step 4: Test management access**

Try accessing a PrivateBox service at https://privatebox.lan:

- From Trusted network: Should work
- From any other VLAN: Should fail (this is correct behavior)

If all tests pass, your VLAN is configured correctly. See [Network Access Rules](./network-access-rules.md) for complete details on what each VLAN can access.

---

### Common issues

**Device gets wrong IP range:**
- Check that you entered the correct VLAN ID in your switch/AP configuration
- Verify the port or SSID is assigned to the VLAN
- Try disconnecting and reconnecting the device

**No IP address assigned:**
- Verify your switch or AP uplink port is configured as a trunk port
- Check that the VLAN is allowed on the trunk
- Confirm the VLAN ID matches the table above

**Internet works on IoT Local or Cameras Local:**
- This indicates the device is on the wrong VLAN
- Verify you configured the VLAN tag correctly (50 for IoT Local, 70 for Cameras Local)
- Check device IP address to confirm which network it joined

**Cannot access any PrivateBox services:**
- If on Trusted network, verify you can access https://10.10.10.1 (OPNsense)
- Check that your device received DNS server 10.10.20.10
- Try accessing by IP: https://10.10.20.10 instead of domain names
- From other VLANs, this is expected behavior (see network access rules)

---

**Disclaimer:** The terminology and steps for configuring VLANs vary significantly between manufacturers (such as Ubiquiti, TP-Link, Netgear, etc.). This guide provides the conceptual overview and the specific VLAN data for your PrivateBox. **You must consult the user manual for your specific switch or access point for detailed instructions.**
