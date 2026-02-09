# Troubleshooting guide

This guide covers the most common issues you might encounter during the initial setup of your PrivateBox.

---

### Problem: I have no internet connection.

This is usually caused by one of three things. Please check them in order.

**Solution 1: Check physical cables**

Ensure your cables are connected correctly. Your PrivateBox has two ports with specific roles.

- The **LEFT** port must be connected to your modem or internet source.
- The **RIGHT** port must be connected to your computer or local network switch.

**Solution 2: Restart your modem**

This is the most common fix. Your Internet Service Provider's modem often needs to be power-cycled to recognize a new device (your PrivateBox) as the network gateway. Many ISP modems "lock" to the MAC address of the first device they see and won't recognize PrivateBox until rebooted.

1. Unplug the power from your modem.
2. Wait 30 seconds (this ensures it fully clears its memory).
3. Plug the power back into your modem.
4. Wait 2-3 minutes for it to fully boot and establish connection.
5. Test your internet connection.

**Note:** Some ISP modems are particularly stubborn. If a single reboot doesn't work, try rebooting it a second time. This resolves the issue in most cases.

**Solution 3: Verify DHCP is disabled on your old router**

As noted in the getting started guide, you'll need to disable the DHCP server on your existing Wi-Fi router. If two devices (your old router and your new PrivateBox) are trying to assign IP addresses on the same network, it'll cause conflicts and prevent devices from connecting properly.

- Please refer back to the [getting-started](getting-started.md) and ensure you have completed this step.

---

### Problem: I can't access the dashboard at `privatebox.lan`.

**Solution 1: Check your network connection**

Ensure the device you're using is connected to your local network (either via Ethernet cable or to your Wi-Fi). You can't access the local dashboard from a mobile data connection (4G/5G).

**Solution 2: Check the address**

- Make sure you've typed the address correctly: `https://privatebox.lan`
- Don't add `.com` or other extensions.
- Remember to accept the security warning, which is normal.

**Solution 3: DHCP conflict**

This is often a symptom of the same DHCP conflict described in "Problem: I have no internet connection." If your old router is still running its own DHCP server, it can prevent your computer from finding the correct address for `privatebox.lan`. Please double-check that you have disabled DHCP on your old router.

---

### Problem: A specific device isn't working as expected.

This is often because the device has been assigned to a network segment (VLAN) that's correctly restricting its access for security reasons.

For example, a smart TV placed on the "IoT (No Internet)" segment won't be able to stream videos, and a security camera on the "Cameras (No Internet)" segment won't be viewable from an app on your phone when you're away from home.

**Solution: Understand network segments**

- Read the [core concepts](core-concepts.md) guide to understand the purpose of each of the seven pre-configured network segments.
- Once you understand the segments, check out the [How to Use VLANs](../advanced/how-to-use-vlans.md) guide to learn how to assign your devices to the correct one.
