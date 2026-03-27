# Frequently asked questions

## General

### What is privatebox?

PrivateBox is a free and open-source project that automates the deployment of a complete network security stack (OPNsense, AdGuard Home, and more) on Proxmox VE. It provides firewall, DNS filtering, and network management on your own hardware.

### Is this really open source?

Yes. All software running on PrivateBox is open source. The automation scripts used to deploy it are also open source and available at https://github.com/Rasped/privatebox. You can inspect, modify, and rebuild everything.

### Are there any subscriptions or ongoing fees?

No. PrivateBox is fully free and open source. You own the hardware, you own the software, you own your data.

### What happened to the hardware appliance?

PrivateBox was originally designed as a commercial hardware appliance sold by SubRosa ApS. Rising RAM and SSD prices made the target hardware economically unviable, so the project pivoted to a pure FOSS release. The software is identical — you just provide your own hardware.

## Hardware

### What hardware do I need?

- **CPU:** Any modern x86_64 CPU (Intel N100/N150/N200/N305 are good choices)
- **RAM:** 8GB minimum, 16GB recommended
- **Storage:** 20GB+ SSD
- **Network:** Dual NICs (two Ethernet ports)
- **Software:** Proxmox VE 9.0 or higher

### How much power does it use?

Depends on your hardware. An Intel N150 mini-PC draws about 10W at idle and 20W under load.

## Network and performance

### What network speeds does it support?

Depends on your hardware and NIC. With an Intel N150 and dual 2.5GbE ports, PrivateBox can handle multi-gigabit routing. With IDS/IPS enabled, it comfortably handles 1+ Gbps.

### Can it replace my existing router?

Yes. PrivateBox acts as your primary router and firewall. You configure your ISP modem in bridge mode and connect it to the WAN port. You'll need a separate WiFi access point.

### Does it work with my ISP?

PrivateBox supports all standard ISP connection types (DHCP, PPPoE, static IP, etc.). If your current router can connect to your ISP, PrivateBox can too.

### How many devices can it handle?

Hundreds. The recommended hardware can handle a typical home or small office network with dozens of devices without issue.

### Can I use it with vlans?

Yes. OPNsense has full VLAN support. PrivateBox comes with pre-configured VLANs for trusted devices, guests, IoT, cameras, and more. See the [VLAN guide](../../advanced/how-to-use-vlans.md).

## Software and features

### What operating system does it run?

PrivateBox runs Proxmox VE as the hypervisor. On top of Proxmox, it runs two VMs:
- OPNsense VM (firewall/router)
- Management VM (running containers for all services)

### Can I add additional services?

Yes. You have full access to Proxmox and can create additional VMs or containers. The Portainer interface makes it easy to add new containerized services.

### How do updates work?

Right now, updates are manual. OPNsense and container images can be updated individually through their respective interfaces. A curated update system is planned but not yet implemented.

### Can I customize the firewall rules?

Yes. You have full access to OPNsense and can configure firewall rules, NAT, VPN, and other advanced features.

### Does it include antivirus or malware protection?

OPNsense includes IDS/IPS (Intrusion Detection/Prevention) capabilities via Suricata. AdGuard Home blocks malicious domains at the DNS level. Together, these provide network-wide threat protection. This is not enabled by default — setup is DIY.

## Setup and configuration

### How long does initial setup take?

About 15 minutes for the automated bootstrap. Physical cabling takes 5 minutes. First login and password changes take another 5-10 minutes.

### Do I need technical knowledge to use it?

You need to be comfortable installing Proxmox VE on bare metal. After that, the bootstrap script handles everything. For advanced features (VLANs, VPN, custom firewall rules), networking knowledge is helpful.

### Where can I get help if i'm stuck?

- **Documentation:** See the [documentation](../../) for guides and how-tos
- **Community:** r/homelab and r/selfhosted communities are excellent resources
- **Issues:** Open a GitHub issue at https://github.com/Rasped/privatebox/issues

## Privacy and security

### Does it phone home or send telemetry?

No. PrivateBox operates entirely locally. No telemetry, no phone-home, no external dependencies. Your network traffic and data never leave your network.

### Is remote access secure?

You can configure remote access in OPNsense using WireGuard or OpenVPN. All connections are encrypted end-to-end. PrivateBox does not automate VPN setup.

### How often are security updates provided?

OPNsense releases security updates regularly (often weekly). You control when to apply them.

### Can it protect my iot devices?

Yes. By placing IoT devices on an isolated VLAN, you can allow them internet access while blocking them from accessing your main network or sending telemetry to manufacturers.

## Comparison questions

### How is this different from ubiquiti dream machine?

- **Privacy:** No forced cloud connection or accounts
- **Subscriptions:** All features included, no paywalls
- **Openness:** Fully open source, not locked to proprietary ecosystem
- **Control:** Complete access to underlying system

### How is this different from firewalla?

- **Cost:** Free software, you only pay for hardware
- **Openness:** Fully open source and auditable
- **Management:** Web UI access, not mobile-only
- **Flexibility:** Full Proxmox hypervisor, run any additional services

### Why not just set it up manually?

You can! But it takes days. PrivateBox automates what would otherwise be a multi-day project of installing Proxmox, configuring VLANs, deploying OPNsense, setting up DNS filtering, configuring a reverse proxy, and wiring it all together. The scripts are the documentation.

## Technical questions

### Can I SSH into it?

Yes. You have full root access to Proxmox and all VMs.

### Does it support ipv6?

Yes. OPNsense has full IPv6 support.

### Can I use it as a NAS too?

The base configuration focuses on networking/security. However, since it runs Proxmox, you can add a TrueNAS VM or additional storage containers.

### What happens if the power goes out?

It'll shut down. When power returns, it boots back up and all services start automatically.

---

**Still have questions?** Open a GitHub issue or check the [full documentation](../../)
