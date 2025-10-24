# PrivateBox Architecture Documentation

This directory contains architectural documentation for PrivateBox features, organized by feature/component.

## How to use this documentation

### Feature overviews
Each feature has a dedicated directory containing:
- `overview.md` - Comprehensive feature documentation with frontmatter metadata
- `adr-NNNN-*.md` - Architecture Decision Records explaining key choices

### Status tracking
Each overview document includes frontmatter with status information:
```yaml
status: implemented | planned | deprecated
implemented_in: v1.0.0  # or null if planned
category: core | security | networking | services | management
complexity: low | medium | high
```

## Implemented features

### Core infrastructure
- **[Recovery System](./recovery-system/)** - Factory reset with password preservation
  - Status: Implemented (v1.0.0)
  - Complexity: High
  - Priority: Critical
  - 7-partition ZFS layout with offline asset storage and encrypted vault

### Networking
- **[Network Architecture](./network-architecture/)** - VLAN segmentation design
  - Status: Implemented (v1.0.0)
  - Complexity: Medium
  - Priority: High
  - 7 network segments (Trusted, Services, Guest, IoT, Cameras)

- **[OPNsense Firewall](./opnsense-firewall/)** - Firewall and routing configuration
  - Status: Implemented (v1.0.0)
  - Complexity: Medium
  - Priority: High
  - VM-based firewall with VLAN support

### Services
- **[AdGuard DNS](./adguard-dns/)** - DNS filtering and ad blocking
  - Status: Implemented (v1.0.0)
  - Complexity: Low
  - Priority: High
  - DNS at 10.10.20.10:53 with upstream to Quad9

- **[Headscale VPN](./headscale-vpn/)** - Self-hosted Tailscale control server
  - Status: Implemented (v1.0.0)
  - Complexity: Medium
  - Priority: Normal
  - API at https://10.10.20.10:4443

### Management and automation
- **[Deployment Automation](./deployment-automation/)** - Ansible-based provisioning
  - Status: Implemented (v1.0.0)
  - Complexity: High
  - Priority: High
  - Semaphore orchestration with Ansible playbooks

## Planned features

_(No planned features documented yet)_

## Templates

- [ADR Template](./adr-template.md) - Architecture Decision Record template
- [Feature Overview Template](./feature-overview-template.md) - Feature documentation template

## Architecture decision records (ADRs)

Cross-feature architectural decisions:
- [ADR-0001: Seven-Partition Recovery Layout](./recovery-system/adr-0001-seven-partition-recovery-layout.md)
- [ADR-0002: Ansible-First Automation Strategy](./deployment-automation/adr-0002-ansible-first-automation.md) *(to be created)*
- [ADR-0003: ZFS Over LVM for Recovery System](./recovery-system/adr-0003-zfs-over-lvm.md) *(to be created)*

## Contributing

When documenting a new feature:
1. Create a directory: `/docs/architecture/[feature-name]/`
2. Copy the [feature overview template](./feature-overview-template.md) to `overview.md`
3. Fill in frontmatter and documentation
4. Create ADRs for major decisions
5. Update this README with the new feature

When making architectural decisions:
1. Copy the [ADR template](./adr-template.md)
2. Number sequentially within the feature directory
3. Use descriptive filenames: `adr-NNNN-short-title.md`
4. Update this README if it's a cross-cutting decision
