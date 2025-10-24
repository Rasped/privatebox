# Getting Started Guide

Welcome to PrivateBox! This guide will walk you through setting up your new network hardware in a few minutes.

## 1. What's in the box

*   The PrivateBox unit
*   The power adapter
*   An ethernet cable

## 2. Physical setup

**Important:** The two network ports on your PrivateBox have specific roles. For the system to work, you must connect them correctly.

![Diagram of the back of the PrivateBox, labeling the left port as WAN and the right port as LAN]

1.  **Connect WAN (Internet):** Plug your internet source (e.g., your modem from your ISP) into the **port on the left**.

2.  **Connect LAN (Your Network):** Use the included Ethernet cable to connect your main computer or a network switch to the **port on the right**.

3.  **Power On:** Plug the power adapter into your PrivateBox. The device will turn on automatically. The light on the front will illuminate.

4.  **Reboot Your Modem (Recommended):** Many ISP modems need to be power-cycled to recognize PrivateBox as the new network gateway:
    - Unplug your modem's power
    - Wait 30 seconds
    - Plug it back in and wait 2-3 minutes for it to fully reconnect

## 3. Configure your existing router

For PrivateBox to manage your network, you must prevent your old router from conflicting with it. The easiest way to do this is to **disable the DHCP server** on your existing Wi-Fi router or access point.

**Alternative:** Some routers have an "Access Point" or "AP Mode" setting. This automatically disables DHCP and is the preferred method if available.

1.  **Log in to your Wi-Fi router.** This usually involves visiting an IP address like `192.168.1.1` in your web browser and entering the admin password found on the router itself.
2.  **Find the DHCP Server setting.** It is commonly found in the "LAN", "Network", or "Advanced Settings" section.
3.  **Disable the DHCP Server.** Select the "Disable" or "Off" option and save your changes. Your router may need to restart.

**Note:** Every router is different. See our [Finding Router Settings](./finding-router-settings.md) guide or [Router Configuration Guide](./router-configuration.md) for specific router instructions.

## 4. First access

1.  **Connect to Your Network:** Make sure your computer is connected to your network (either via an Ethernet cable to the port on the right, or to your existing Wi-Fi).
2.  **Visit the Dashboard:** Open a web browser and go to: **`http://privatebox.lan`**

    *If privatebox.lan does not work, try `http://10.10.10.1` instead.*

3.  **Accept the Security Warning:** You will likely see a security warning page. **This is normal and expected.** It appears because your PrivateBox is using a private, self-signed security certificate instead of one from a public authority.
    *   Click the **"Advanced"** button.
    *   Click **"Proceed to privatebox.lan"** or **"Accept the Risk and Continue"**.

## 5. That's it

Your network is now protected by PrivateBox. All devices connected to your network will have their ads and trackers blocked automatically.

### Next steps

Now that you're up and running, here's what you can do next:

*   To understand the new security features of your network, read the **[Core Concepts](core-concepts.md)** guide.
*   To learn how to segment your network for IoT devices or guests, see the **[How to Use VLANs](../advanced/how-to-use-vlans.md)** guide.
