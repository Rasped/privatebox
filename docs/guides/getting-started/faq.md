# Frequently Asked Questions

## General

### What is PrivateBox?

PrivateBox is a pre-configured network security appliance running open-source software (OPNsense, AdGuard Home, Headscale, and more) on Proxmox VE. It provides firewall, DNS filtering, VPN, and network management capabilities in a single, energy-efficient device.

### Is this really open source?

Yes. All software running on PrivateBox is open source. The automation scripts used to deploy it are also open source and available at https://github.com/subrosadev/privatebox. You can inspect, modify, and rebuild everything.

### What's the difference between the open-source project and the hardware appliance?

The open-source project provides scripts to deploy the PrivateBox stack on any compatible hardware running Proxmox. The hardware appliance is a pre-built, pre-tested mini PC with everything installed and ready to use out of the box.

### Are there any subscriptions or ongoing fees?

No. Never. All features are included with your purchase. Software updates are provided for free, forever. You own the hardware, you own the software, you own your data.

### What happens if Sub Rosa goes out of business?

Nothing changes. You have complete control over the system. All software is open source, and you can maintain, update, and modify it independently. There's no cloud dependency or licensing server.

## Hardware & specifications

### What are the hardware specifications?

- **CPU:** Intel N150 (4 cores, up to 3.6 GHz)
- **RAM:** 16GB DDR5
- **Storage:** 256GB Enterprise-grade SSD
- **Network:** Dual 2.5GbE Intel i226-V ports
- **Power:** ~7W idle, ~14W under load
- **Cooling:** Active (quiet fan)

### Can I upgrade the hardware?

The RAM and storage are user-accessible and can be upgraded. The system supports up to 32GB RAM. For detailed upgrade instructions, see the Hardware Modifications section in the documentation.

### How much power does it use?

Approximately 7W at idle and 14W under full load. Annual power consumption is roughly €15-20 at typical European electricity rates.

### Is it loud?

No. The active cooling system is designed to be quiet enough for home office or living room placement. Under normal operation, it's barely audible.

### Can I rack mount it?

The standard chassis is a small form factor desktop. Third-party rack mounting brackets for this form factor are available separately. Future versions may offer official rack mount options.

## Network & performance

### What network speeds does it support?

PrivateBox can handle multi-gigabit routing. With IDS/IPS enabled, it comfortably handles 1+ Gbps. The dual 2.5GbE ports support up to 2.5 Gbps connections.

### Can it replace my existing router?

Yes. PrivateBox is designed to be your primary router and firewall. You'll configure your ISP modem in bridge mode and connect it to PrivateBox's WAN port.

### Does it work with my ISP?

PrivateBox supports all standard ISP connection types (DHCP, PPPoE, static IP, etc.). If your current router can connect to your ISP, PrivateBox can too.

### How many devices can it handle?

Hundreds. The exact number depends on your network activity, but the hardware is more than capable of handling a typical home or small office network with dozens of devices.

### Can I use it with VLANs?

Yes. OPNsense has full VLAN support. You can create isolated network segments for IoT devices, guests, servers, etc.

## Software & features

### What operating system does it run?

PrivateBox runs Proxmox VE as the hypervisor. On top of Proxmox, it runs three VMs:
- OPNsense VM (firewall/router)
- Management VM (running containers for all services)
- Subnet Router VM (for VPN routing)

### Can I add additional services?

Yes. You have full access to Proxmox and can create additional VMs or containers. The Portainer interface makes it easy to add new containerized services.

### How do updates work?

The system includes a curated update channel. We test all updates before making them available. You can configure automatic weekly updates or manually approve each update. You control when updates are applied.

### Can I customize the firewall rules?

Yes. You have full access to OPNsense and can configure any firewall rules, NAT, VPN, or advanced features you need.

### Does it include antivirus or malware protection?

OPNsense includes IDS/IPS (Intrusion Detection/Prevention) capabilities via Suricata. AdGuard Home blocks malicious domains at the DNS level. Together, these provide network-wide threat protection.

## Setup & configuration

### How long does initial setup take?

Physical setup takes about 5 minutes (plug in cables, power on). First login and password changes take another 5-10 minutes. Basic network configuration (WAN setup, WiFi if applicable) takes 10-20 minutes depending on your requirements.

### Do I need technical knowledge to use it?

Basic network knowledge is helpful but not required. The Quick Start Guide and online documentation walk you through initial setup step-by-step. For advanced features (VLANs, VPN, custom firewall rules), some networking knowledge is beneficial.

### Can I reset to factory defaults if I mess something up?

Yes. Proxmox includes VM snapshots and backups. You can roll back to a previous state at any time. Full factory reset instructions are included in the documentation.

### Where can I get help if I'm stuck?

- **Documentation:** https://privatebox.com/docs (comprehensive guides and how-tos)
- **Community:** r/homelab and r/selfhosted communities are excellent resources
- **Direct Support:** support@subrosa.dev for hardware or warranty issues

## Privacy & security

### Does it phone home or send telemetry?

No. PrivateBox operates entirely locally. No telemetry, no phone-home, no external dependencies. Your network traffic and data never leave your network.

### Is remote access secure?

Yes. Remote access is provided via Headscale (self-hosted Tailscale alternative), which uses WireGuard VPN. Only Headscale is exposed to the internet, and all connections are encrypted end-to-end.

### How often are security updates provided?

OPNsense releases security updates regularly (often weekly). We test these updates and make them available through the curated update channel. You control when to apply them.

### Can it protect my IoT devices?

Yes. By placing IoT devices on an isolated VLAN, you can allow them internet access while blocking them from accessing your main network or sending telemetry to manufacturers.

## Warranty & support

### What's the warranty period?

PrivateBox includes a 2-year legal guarantee as required by EU law. This covers defects in materials and workmanship.

### What if something breaks?

Contact support@subrosa.dev with your order number and a description of the issue. We'll troubleshoot remotely first. If hardware replacement is needed, we'll provide RMA instructions.

### Can I return it if I change my mind?

EU customers have a 14-day right of withdrawal. You can return the product for any reason within 14 days of receipt for a full refund (you pay return shipping).

### Is there paid support available?

Currently, support is provided on a best-effort basis via email and community resources. Paid support tiers may be introduced in the future based on demand.

## Shipping & availability

### Where do you ship?

Currently, we ship to all EU member states. UK and US shipping are planned for future phases after the initial EU launch is successful.

### How long does shipping take?

Standard shipping within the EU is 2-5 business days. Tracking information is provided when your order ships.

### What about customs and import fees?

For EU customers, there are no customs fees. VAT is included in the displayed price.

## Comparison questions

### How is this different from Ubiquiti Dream Machine?

- **Privacy:** No forced cloud connection or accounts
- **Subscriptions:** All features included, no paywalls
- **Openness:** Fully open source, not locked to proprietary ecosystem
- **Control:** Complete access to underlying system

### How is this different from Firewalla?

- **Price:** Better price-to-performance ratio
- **Hardware:** Newer CPU (2023 vs older generation), active cooling for sustained performance
- **EU Focus:** Warehoused and shipped from EU, no import delays or fees
- **Management:** Web UI + mobile options (not mobile-only)

### How is this different from Protectli?

- **Setup:** Pre-configured and ready to use (Protectli requires full DIY setup)
- **Support:** Includes tested update channel and setup assistance
- **Convenience:** Plug and play vs. building from scratch

### How is this different from pfSense/Netgate appliances?

- **Platform:** Proxmox-based (allows additional VMs/services), not bare metal
- **Modern UI:** OPNsense's modern interface vs. pfSense's older UI
- **Price:** Better value at the €400-500 price point
- **Flexibility:** Runs services beyond just firewall (dashboard, VPN, DNS, automation)

### Why not just build it myself?

You can! The scripts are open source. Building yourself saves money but costs time:
- Hardware research and compatibility verification
- Component sourcing and assembly
- OS installation and configuration
- Troubleshooting and debugging
- Ongoing maintenance planning

PrivateBox is for those who value their time or want a tested, warranty-backed solution.

## Technical questions

### Can I SSH into it?

Yes. You have full root access to Proxmox and all VMs. SSH is available for advanced users.

### Does it support IPv6?

Yes. OPNsense has full IPv6 support.

### Can I use it as a NAS too?

The base configuration focuses on networking/security. However, since it runs Proxmox, you can add a TrueNAS VM or additional storage containers if you have storage expansion needs.

### What happens if the power goes out?

The system will gracefully shut down if power is lost. When power returns, it will automatically boot up. For critical deployments, adding a UPS (Uninterruptible Power Supply) is recommended.

### Can I cluster multiple units?

OPNsense supports HA (High Availability) clustering. This is an advanced configuration covered in the documentation.

---

**Still have questions?** Email support@subrosa.dev or check the full documentation at https://privatebox.com/docs
