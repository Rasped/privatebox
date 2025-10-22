# Known Issues

This document tracks known bugs and issues that need to be addressed in PrivateBox.

## Critical Issues

### 1. NTP Queries from All VMs and Containers
**Status**: Open
**Impact**: High
**Description**: All VMs and containers are making NTP queries, potentially causing network noise or timing sync issues.
**Affected Components**: All VMs, all containers

### 2. Proxmox Not Removed from WAN Side
**Status**: Resolved (2025-10-22)
**Impact**: Critical - Security Risk
**Description**: Proxmox host is still exposed on the WAN side, creating a security vulnerability. Should only be accessible from LAN side.
**Affected Components**: Proxmox host networking
**Resolution**: Updated `proxmox-go-live.yml` to remove IP address and gateway from vmbr0 (WAN bridge) before configuring vmbr1.20. Run this playbook via Semaphore to apply the fix.

### 3. Proxmox Not Accessible on LAN Side
**Status**: Resolved (2025-10-22)
**Impact**: Critical - Operational
**Description**: Proxmox host is not accessible on LAN side via SSH or Web UI. Expected to be accessible at 10.10.20.20:8006.
**Affected Components**: Proxmox host networking, SSH access, Web UI
**Resolution**: Updated `proxmox-go-live.yml` to properly configure vmbr1.20 with gateway and ensure Proxmox is accessible at 10.10.20.20 on Services VLAN. Run this playbook via Semaphore to apply the fix.

### 4. Ping from HOMER Does Not Work
**Status**: Open
**Impact**: Medium
**Description**: Ping functionality from HOMER dashboard does not work, at least on HTTPS without domain configuration.
**Affected Components**: HOMER service

---

**Last Updated**: 2025-10-22
