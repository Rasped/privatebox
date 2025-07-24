# Firewall Rules Matrix Template

**Date**: [Date]  
**Version**: [Version]  
**Author**: [Author]

## Overview

This document details all firewall rules for the PrivateBox network segmentation. Each rule is documented with justification and technical specifications.

## Rule Naming Convention

Rules follow the format: `[PRIORITY]-[SOURCE]-[DEST]-[SERVICE]-[ACTION]`
- Priority: 100-999 (lower = higher priority)
- Source: VLAN name or ANY
- Dest: VLAN name or ANY
- Service: Port/protocol or service name
- Action: ALLOW or DENY

## Inter-VLAN Rules

### Management VLAN (10.0.10.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 100-MGMT-ANY-ANY-ALLOW | 10.0.10.0/24 | ANY | ANY | ANY | ALLOW | Yes | Management can access all |
| | | | | | | | |

### Services VLAN (10.0.20.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 200-SVC-ANY-HTTPS-ALLOW | 10.0.20.0/24 | 0.0.0.0/0 | 443 | TCP | ALLOW | Yes | Services to Internet HTTPS |
| 201-SVC-ANY-HTTP-ALLOW | 10.0.20.0/24 | 0.0.0.0/0 | 80 | TCP | ALLOW | Yes | Services to Internet HTTP |
| | | | | | | | |

### LAN VLAN (10.0.30.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 300-LAN-SVC-DNS-ALLOW | 10.0.30.0/24 | 10.0.20.21 | 53 | UDP/TCP | ALLOW | Yes | LAN to AdGuard DNS |
| 301-LAN-ANY-HTTPS-ALLOW | 10.0.30.0/24 | 0.0.0.0/0 | 443 | TCP | ALLOW | Yes | LAN to Internet HTTPS |
| | | | | | | | |

### IoT VLAN (10.0.40.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 400-IOT-SVC-DNS-ALLOW | 10.0.40.0/24 | 10.0.20.21 | 53 | UDP/TCP | ALLOW | Yes | IoT to AdGuard DNS |
| 401-IOT-ANY-NTP-ALLOW | 10.0.40.0/24 | 0.0.0.0/0 | 123 | UDP | ALLOW | Yes | IoT NTP time sync |
| | | | | | | | |

## Inbound Rules (WAN → Internal)

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 500-WAN-ANY-ANY-DENY | 0.0.0.0/0 | RFC1918 | ANY | ANY | DENY | N/A | Block all inbound by default |
| | | | | | | | |

## NAT Rules

### Outbound NAT (SNAT)

| VLAN | Source Network | NAT IP | Description |
|------|----------------|--------|-------------|
| Management | 10.0.10.0/24 | WAN IP | Management to Internet |
| Services | 10.0.20.0/24 | WAN IP | Services to Internet |
| LAN | 10.0.30.0/24 | WAN IP | LAN to Internet |
| IoT | 10.0.40.0/24 | WAN IP | IoT to Internet (limited) |

### Port Forwarding (DNAT)

| External Port | Internal IP | Internal Port | Protocol | Description |
|---------------|-------------|---------------|----------|-------------|
| [None by default] | | | | |

## Special Rules

### DHCP Rules

| Rule ID | Source | Destination | Port | Protocol | Action | Description |
|---------|--------|-------------|------|----------|--------|-------------|
| 600-DHCP-REQUEST | 0.0.0.0 | 255.255.255.255 | 67 | UDP | ALLOW | DHCP requests |
| 601-DHCP-REPLY | DHCP Server | 255.255.255.255 | 68 | UDP | ALLOW | DHCP replies |

### ICMP Rules

| Rule ID | Source | Destination | Type | Action | Description |
|---------|--------|-------------|------|--------|-------------|
| 700-ICMP-ECHO-MGMT | 10.0.10.0/24 | ANY | Echo Request | ALLOW | Ping from management |
| 701-ICMP-PMTU | ANY | ANY | Fragmentation Needed | ALLOW | Path MTU discovery |

## Default Policies

| Chain | Default Action | Description |
|-------|----------------|-------------|
| FORWARD | DENY | Deny all inter-VLAN by default |
| INPUT | DENY | Deny all to firewall by default |
| OUTPUT | ALLOW | Allow firewall outbound |

## Rate Limiting Rules

| Service | Rate Limit | Burst | Action | Description |
|---------|------------|-------|--------|-------------|
| DNS | 100/sec | 150 | LOG+ACCEPT | DNS query rate limit |
| SSH | 3/min | 5 | DROP | SSH brute force protection |

## Logging Rules

| Traffic Type | Log Level | Sample Rate | Description |
|--------------|-----------|-------------|-------------|
| Denied packets | WARNING | 1/10 | Log 10% of denies |
| Allowed management | INFO | 1/100 | Sample management traffic |

## Notes

1. All rules are stateful unless specified otherwise
2. Established/related connections are allowed by default
3. IPv6 rules mirror IPv4 unless specified
4. Review and update quarterly

## Change Log

| Date | Change | Author | Approved By |
|------|--------|--------|-------------|
| | | | |