# OPNsense Role

This role manages OPNsense firewall deployment and configuration on Proxmox infrastructure.

## Sub-roles

- **provision**: Handles VM creation and OS installation
- **base**: Performs initial configuration via API
- **firewall**: Manages firewall rules (to be implemented)
- **vpn**: Configures VPN services (to be implemented)

## Requirements

- Proxmox host with API access
- Network configuration with WAN and LAN bridges
- Sufficient resources (2 CPU, 2GB RAM, 20GB disk)

## Dependencies

- proxmox role (for VM provisioning)

## Usage

Include the appropriate sub-role in your playbook:

```yaml
- name: Provision OPNsense VM
  include_role:
    name: opnsense/provision

- name: Configure OPNsense base
  include_role:
    name: opnsense/base
```