# Firewall Rules Matrix

**Date**: 2025-07-24  
**Version**: 1.0  
**Author**: Claude

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
| 100-MGMT-ANY-ANY-ALLOW | 10.0.10.0/24 | ANY | ANY | ANY | ALLOW | Yes | Management has full access |
| 110-MGMT-SELF-SSH-ALLOW | 10.0.10.0/24 | 10.0.10.1 | 22 | TCP | ALLOW | Yes | SSH to OPNsense |
| 111-MGMT-SELF-HTTPS-ALLOW | 10.0.10.0/24 | 10.0.10.1 | 443 | TCP | ALLOW | Yes | HTTPS to OPNsense GUI |

### Services VLAN (10.0.20.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 200-SVC-INTERNET-HTTPS-ALLOW | 10.0.20.0/24 | !RFC1918 | 443 | TCP | ALLOW | Yes | Services to Internet HTTPS |
| 201-SVC-INTERNET-HTTP-ALLOW | 10.0.20.0/24 | !RFC1918 | 80 | TCP | ALLOW | Yes | Services to Internet HTTP |
| 202-SVC-INTERNET-DNS-ALLOW | 10.0.20.0/24 | !RFC1918 | 853 | TCP | ALLOW | Yes | DNS over TLS |
| 203-SVC-INTERNET-NTP-ALLOW | 10.0.20.0/24 | !RFC1918 | 123 | UDP | ALLOW | Yes | NTP time sync |
| 210-SVC-MGMT-DENY | 10.0.20.0/24 | 10.0.10.0/24 | ANY | ANY | DENY | N/A | Block services to management |
| 211-SVC-LAN-DENY | 10.0.20.0/24 | 10.0.30.0/24 | ANY | ANY | DENY | N/A | Block services to LAN |
| 212-SVC-IOT-DENY | 10.0.20.0/24 | 10.0.40.0/24 | ANY | ANY | DENY | N/A | Block services to IoT |

### LAN VLAN (10.0.30.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 300-LAN-SVC-DNS-ALLOW | 10.0.30.0/24 | 10.0.20.21 | 53 | UDP/TCP | ALLOW | Yes | LAN to AdGuard DNS |
| 301-LAN-SVC-WEBUI-ALLOW | 10.0.30.0/24 | 10.0.20.21 | 8080 | TCP | ALLOW | Yes | LAN to AdGuard WebUI |
| 302-LAN-SVC-PORTAINER-ALLOW | 10.0.30.0/24 | 10.0.20.21 | 9000 | TCP | ALLOW | Yes | LAN to Portainer |
| 303-LAN-SVC-SEMAPHORE-ALLOW | 10.0.30.0/24 | 10.0.20.21 | 3000 | TCP | ALLOW | Yes | LAN to Semaphore |
| 310-LAN-INTERNET-ANY-ALLOW | 10.0.30.0/24 | !RFC1918 | ANY | ANY | ALLOW | Yes | LAN full Internet access |
| 320-LAN-MGMT-DENY | 10.0.30.0/24 | 10.0.10.0/24 | ANY | ANY | DENY | N/A | Block LAN to management |
| 321-LAN-IOT-DENY | 10.0.30.0/24 | 10.0.40.0/24 | ANY | ANY | DENY | N/A | Block LAN to IoT |

### IoT VLAN (10.0.40.0/24) → Other VLANs

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 400-IOT-SVC-DNS-ALLOW | 10.0.40.0/24 | 10.0.20.21 | 53 | UDP/TCP | ALLOW | Yes | IoT to AdGuard DNS |
| 401-IOT-INTERNET-HTTP-ALLOW | 10.0.40.0/24 | !RFC1918 | 80 | TCP | ALLOW | Yes | IoT HTTP updates |
| 402-IOT-INTERNET-HTTPS-ALLOW | 10.0.40.0/24 | !RFC1918 | 443 | TCP | ALLOW | Yes | IoT HTTPS |
| 403-IOT-INTERNET-NTP-ALLOW | 10.0.40.0/24 | !RFC1918 | 123 | UDP | ALLOW | Yes | IoT NTP time sync |
| 404-IOT-INTERNET-MQTT-ALLOW | 10.0.40.0/24 | !RFC1918 | 8883 | TCP | ALLOW | Yes | IoT MQTT over TLS |
| 410-IOT-MGMT-DENY | 10.0.40.0/24 | 10.0.10.0/24 | ANY | ANY | DENY | N/A | Block IoT to management |
| 411-IOT-SVC-DENY | 10.0.40.0/24 | 10.0.20.0/24 | ANY | ANY | DENY | N/A | Block IoT to services (except DNS) |
| 412-IOT-LAN-DENY | 10.0.40.0/24 | 10.0.30.0/24 | ANY | ANY | DENY | N/A | Block IoT to LAN |

## Inbound Rules (WAN → Internal)

| Rule ID | Source | Destination | Port | Protocol | Action | Stateful | Description |
|---------|--------|-------------|------|----------|--------|----------|-------------|
| 500-WAN-ALL-DENY | 0.0.0.0/0 | RFC1918 | ANY | ANY | DENY | N/A | Block all inbound by default |
| 501-WAN-ESTABLISHED-ALLOW | 0.0.0.0/0 | ANY | ANY | ANY | ALLOW | Yes | Allow established connections |

## NAT Rules

### Outbound NAT (SNAT)

| VLAN | Source Network | NAT IP | Description |
|------|----------------|--------|-------------|
| Management | 10.0.10.0/24 | WAN IP | Management to Internet |
| Services | 10.0.20.0/24 | WAN IP | Services to Internet |
| LAN | 10.0.30.0/24 | WAN IP | LAN to Internet |
| IoT | 10.0.40.0/24 | WAN IP | IoT to Internet (limited ports) |

### Port Forwarding (DNAT)

| External Port | Internal IP | Internal Port | Protocol | Description |
|---------------|-------------|---------------|----------|-------------|
| None | - | - | - | No inbound services exposed |

## Special Rules

### DHCP Rules

| Rule ID | Source | Destination | Port | Protocol | Action | Description |
|---------|--------|-------------|------|----------|--------|-------------|
| 600-DHCP-REQUEST | 0.0.0.0 | 255.255.255.255 | 67 | UDP | ALLOW | DHCP requests |
| 601-DHCP-REPLY | DHCP Server | 255.255.255.255 | 68 | UDP | ALLOW | DHCP replies |
| 602-DHCP-LAN | 10.0.30.0/24 | 10.0.30.1 | 67 | UDP | ALLOW | LAN DHCP to gateway |
| 603-DHCP-IOT | 10.0.40.0/24 | 10.0.40.1 | 67 | UDP | ALLOW | IoT DHCP to gateway |

### ICMP Rules

| Rule ID | Source | Destination | Type | Action | Description |
|---------|--------|-------------|------|--------|-------------|
| 700-ICMP-ECHO-MGMT | 10.0.10.0/24 | ANY | Echo Request | ALLOW | Ping from management |
| 701-ICMP-ECHO-LAN | 10.0.30.0/24 | !RFC1918 | Echo Request | ALLOW | Ping to Internet from LAN |
| 702-ICMP-PMTU | ANY | ANY | Fragmentation Needed | ALLOW | Path MTU discovery |
| 703-ICMP-TIMEEXCEEDED | ANY | ANY | Time Exceeded | ALLOW | Traceroute support |

## Default Policies

| Chain | Default Action | Description |
|-------|----------------|-------------|
| FORWARD | DENY | Deny all inter-VLAN by default |
| INPUT | DENY | Deny all to firewall except management |
| OUTPUT | ALLOW | Allow firewall outbound |

## Rate Limiting Rules

| Service | Rate Limit | Burst | Action | Description |
|---------|------------|-------|--------|-------------|
| DNS | 100/sec | 150 | LOG+ACCEPT | DNS query rate limit per source IP |
| SSH | 3/min | 5 | DROP | SSH brute force protection |
| HTTPS | 10/sec | 20 | LOG+ACCEPT | Web interface protection |

## Logging Rules

| Traffic Type | Log Level | Sample Rate | Description |
|--------------|-----------|-------------|-------------|
| Denied packets | WARNING | 1/10 | Log 10% of denies to prevent log spam |
| Allowed management | INFO | 1/100 | Sample management traffic |
| New connections | INFO | 1/20 | Sample new connection establishments |

## Ansible Implementation

### Firewall Rule Variables
```yaml
firewall_rules:
  # Management VLAN rules
  - rule_id: "100-MGMT-ANY-ANY-ALLOW"
    interface: "MGMT"
    source: "MGMT_net"
    destination: "any"
    action: "pass"
    log: true
    description: "Management full access"

  # Services VLAN rules  
  - rule_id: "300-LAN-SVC-DNS-ALLOW"
    interface: "LAN"
    source: "LAN_net"
    destination: "10.0.20.21"
    destination_port: "53"
    protocol: "udp,tcp"
    action: "pass"
    description: "LAN to AdGuard DNS"

# Network aliases
network_aliases:
  - name: "MGMT_net"
    content: "10.0.10.0/24"
    description: "Management VLAN"
  - name: "SVC_net"
    content: "10.0.20.0/24"
    description: "Services VLAN"
  - name: "LAN_net"
    content: "10.0.30.0/24"
    description: "LAN VLAN"
  - name: "IOT_net"
    content: "10.0.40.0/24"
    description: "IoT VLAN"
  - name: "RFC1918"
    content: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    description: "Private IP ranges"
```

## Notes

1. All rules are stateful unless specified otherwise
2. Established/related connections are allowed by default
3. IPv6 rules mirror IPv4 (not shown for brevity)
4. Rules are processed in priority order (lower number = higher priority)
5. DNS rule for services precedes general deny rules
6. Management VLAN has unrestricted access for administration
7. Services isolated except for Internet access
8. IoT heavily restricted to prevent lateral movement

## Change Log

| Date | Change | Author | Approved By |
|------|--------|--------|-------------|
| 2025-07-24 | Initial rule matrix created | Claude | Pending |