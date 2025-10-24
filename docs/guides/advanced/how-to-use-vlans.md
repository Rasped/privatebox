# Advanced: How to Use VLANs

This guide explains how to use the pre-configured VLANs (Virtual LANs) on your PrivateBox to segment your network. 

---

### Prerequisite: VLAN-Capable Hardware

To use this feature, you **must** have your own network switch or wireless access point (AP) that is VLAN-capable. PrivateBox creates and manages the secure network segments, but your hardware is responsible for assigning devices to them. This functionality is often found in prosumer or business-grade network equipment.

---

### The Concept

Your PrivateBox has a single physical LAN port, but it broadcasts multiple, isolated networks over that one connection. Each of these networks is identified by a unique "VLAN ID" or "Tag".

Your VLAN-capable switch or AP can read these tags. You can configure your hardware to, for example, assign a specific port on your switch to VLAN 30, or create a new Wi-Fi network that places any connected device onto VLAN 40.

This allows you to place devices into the correct security zone.

---

### PrivateBox VLAN Architecture

This table contains the information you will need to configure your own hardware.

| VLAN ID | Network       | Purpose                                      | DHCP Pool         | Notes                            |
|:--------|:--------------|:---------------------------------------------|:------------------|:---------------------------------|
| Untagged| 10.10.10.0/24 | **Trusted** - Family devices & trusted computers | 10.10.10.100-200  | No VLAN tag required             |
| 20      | 10.10.20.0/24 | **Services** - PrivateBox infrastructure         | None (all static) | Management VM, Proxmox, OPNsense |
| 30      | 10.10.30.0/24 | **Guest** - Visitor devices                      | 10.10.30.100-120  | Internet-only access             |
| 40      | 10.10.40.0/24 | **IoT Cloud** - Smart devices requiring internet | 10.10.40.100-200  | Smart TVs, voice assistants      |
| 50      | 10.10.50.0/24 | **IoT Local** - Local-only smart devices         | 10.10.50.100-200  | No internet access               |
| 60      | 10.10.60.0/24 | **Cameras Cloud** - Cameras with cloud recording | 10.10.60.100-150  | Ring, Nest, etc.                 |
| 70      | 10.10.70.0/24 | **Cameras Local** - Local-only cameras           | 10.10.70.100-150  | No internet access               |

---

### Generic Workflow

While the specific steps depend on your hardware, the general process is as follows:

1.  **Connect Hardware:** Connect your VLAN-capable switch or access point to the **RIGHT (LAN)** port on your PrivateBox.

2.  **Log in to Your Switch/AP:** Open the management interface for your network hardware.

3.  **Create a New Network/VLAN:** Find the section for creating a new LAN, network, or wireless network (SSID).

4.  **Enter the VLAN ID:** When prompted for a **VLAN ID** or **VLAN Tag**, enter the corresponding number from the table above. For example, to create a guest Wi-Fi network, you would enter `30`.

5.  **Assign the Network:** You can now either assign a specific physical port on your switch to this new VLAN, or, if you are creating a wireless network, save the new Wi-Fi SSID.

Any device connected to that port or that Wi-Fi network will now be automatically placed in the correct security zone managed by your PrivateBox.

---

**Disclaimer:** The terminology and steps for configuring VLANs vary significantly between manufacturers (such as Ubiquiti, TP-Link, Netgear, etc.). This guide provides the conceptual overview and the specific VLAN data for your PrivateBox. **You must consult the user manual for your specific switch or access point for detailed instructions.**
