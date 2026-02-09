# Core concepts

Your PrivateBox is designed around a single, core principle: *your data isn't a product.* These features aren't just technical add-ons; they're the tools that deliver on that promise. This guide explains the purpose of each one in simple terms.

---

### Network segments (VLANs)

**The concept:** Think of your home network as a single, large open-plan room where everyone can see and interact with everyone else. Network segmentation, using a technology called VLANs, is like building digital walls to create separate, secure rooms. What happens in one room cannot affect the others unless you specifically create a doorway.

Your PrivateBox comes with several pre-configured "rooms" for different purposes:

*   **Trusted:** Your personal computers, laptops, and phones
*   **Services:** Where PrivateBox services run (only accessible from Trusted)
*   **Guest:** Visitor devices (internet only, cannot access your network)
*   **IoT:** Smart devices like TVs and speakers (with separate cloud/local networks)
*   **Cameras:** Security cameras (with separate cloud/local networks)


For complete details on all seven network segments, see the [VLAN configuration guide](../../advanced/how-to-use-vlans.md).

---

### The firewall

**The concept:** The firewall is the digital guard or bouncer standing at the single entry point to your entire network. It inspects every connection trying to get in from the internet.

**What it does:** By default, it operates on a "deny all" policy. It blocks any unsolicited connection attempt, ensuring that only legitimate traffic that you have requested is allowed onto your network.

**What it doesn't do:**
*   It's not an antivirus. It doesn't scan your files for malware. You still need good antivirus software on your computers.
*   It doesn't prevent you from visiting a malicious website. It protects you from outside attacks, but you can still walk out the door into a dangerous neighborhood.

---

### Ad & tracker blocking

**The concept:** Think of the internet's address book as a giant phone book (called DNS). When your computer wants to visit `google.com`, it asks DNS for the number. The Ad & Tracker blocker on your PrivateBox uses a modified phone book that simply refuses to look up the numbers for domains known to serve ads and trackers.

**What it does:** Because this happens at the network level, many ads and trackers are blocked for *every device* in your home (computers, phones, and even smart TVs) without installing any software on them. This protects your privacy and can even make websites load faster.

**What it doesn't do:** It can't block 100% of ads. Some ads (like on YouTube or sponsored posts on social media) are served from the same "phone number" as the content you want to see. Blocking them would block the content itself.

---

### VPN (virtual private network)

**The concept:** The VPN creates a secure, encrypted "tunnel" from your device (like your laptop at a coffee shop) back to your home network.

**What it does:** It lets you access your home network when you're away. It can also protect your traffic on public Wi-Fi by routing it through your home connection.

**What it's not:** This isn't a commercial VPN service designed to make you anonymous or change your geographic location to bypass content restrictions. Its purpose is to give you secure access to *your own network*, not to hide your identity from third-party websites.

**How it works in PrivateBox:** PrivateBox does not automatically set up VPN access. If you want remote access, configure WireGuard or OpenVPN in OPNsense.
