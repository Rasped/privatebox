# Known Issues

This document tracks known bugs and issues that need to be addressed in PrivateBox.

## Critical Issues

### 1. NTP Queries from All VMs and Containers
**Status**: Open
**Impact**: High
**Description**: All VMs and containers are making NTP queries, potentially causing network noise or timing sync issues.
**Affected Components**: All VMs, all containers

### 2. Proxmox Not Removed from WAN Side
**Status**: Open
**Impact**: Critical - Security Risk
**Description**: Proxmox host is still exposed on the WAN side, creating a security vulnerability. Should only be accessible from LAN side.
**Affected Components**: Proxmox host networking

### 3. Proxmox Not Accessible on LAN Side
**Status**: Open
**Impact**: Critical - Operational
**Description**: Proxmox host is not accessible on LAN side via SSH or Web UI. Expected to be accessible at 10.10.20.20:8006.
**Affected Components**: Proxmox host networking, SSH access, Web UI

### 4. Ping from HOMER Does Not Work
**Status**: Open
**Impact**: Medium
**Description**: Ping functionality from HOMER dashboard does not work, at least on HTTPS without domain configuration.
**Affected Components**: HOMER service

---

**Last Updated**: 2025-10-22
