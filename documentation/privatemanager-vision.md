# PrivateManager - Vision Document

## Overview

PrivateManager is a customer-friendly web interface for managing and troubleshooting PrivateBox. It provides a polished, focused UI on top of Semaphore's automation capabilities.

## The Problem

**Semaphore is powerful but not customer-friendly:**
- Long, cluttered list of playbooks
- Technical interface designed for DevOps professionals
- No built-in diagnostics or health monitoring
- Not polished enough for consumer product

**Customers need simple answers:**
- "Is everything working?"
- "What's broken and why?"
- "How do I update my system?"
- "How do I share diagnostic info with support?"

## The Solution

PrivateManager is a **diagnostic and management hub** that:
- Shows clear system status (this is up, this is down, this cannot reach that)
- Triggers Semaphore playbooks through a cleaner, focused interface
- Provides easy diagnostics for customer self-service and support
- Generates comprehensive diagnostic reports

## Core Philosophy

> "I have a problem, let me check the manager"

The customer opens PrivateManager and **immediately sees** what's working and what's not, without needing to understand Ansible, VLANs, or networking.

## Key Features

### 1. System Health Dashboard
- Clear visual status of all services
- CPU/RAM/Disk/Temperature monitoring
- Network connectivity status
- Service reachability checks

### 2. Playbook Triggering
- Curated list of common operations (not every Semaphore template)
- Clean, simple triggers (not exposed implementation details)
- Variable passing to playbooks (if Semaphore API supports)
- Live or near-live log viewing

### 3. Diagnostics & Troubleshooting
- Network diagnostics (connectivity, DNS, routing)
- Service health checks (deeper than just up/down)
- Log viewer for key services
- **"Generate Report" button** - Creates comprehensive diagnostic snapshot for support

### 4. Update Management
- Trigger safe updates (integrates with update-architecture.md ZFS snapshots)
- Show available updates
- Trigger rollbacks to snapshots
- Individual service updates (not "update all" initially)

## Architecture

### Integration
- **Uses Semaphore API** - Doesn't run playbooks itself, just triggers Semaphore
- **Securely stores Semaphore API key** - Authenticated access to automation
- **Semaphore remains accessible** - Power users can still use Semaphore directly
- **Reads system metrics** - Via Proxmox API, SSH, or service APIs

### Deployment
- Container on Management VM (like AdGuard, Portainer, etc.)
- Accessible via Caddy at `privatemanager.lan`
- Uses same SERVICES_PASSWORD authentication
- Web-based SPA (technology choice: whatever fits best for speed/simplicity)

### Relationship to Other Services
```
Customer ──> PrivateManager ──> Semaphore API ──> Ansible Playbooks
                    │
                    ├──> Proxmox API (metrics, VM status)
                    ├──> Service APIs (AdGuard, OPNsense health)
                    └──> System metrics (CPU, RAM, disk, network)
```

## Target Users

### Product Customers (Primary)
- Non-technical consumers who bought PrivateBox appliance
- Want simple "is it working?" answers
- Need guided troubleshooting
- Don't want to learn Ansible/networking

### FOSS Users (Secondary, Maybe)
- Technical users who want cleaner UX
- Appreciate diagnostic tools
- Still have Semaphore access for advanced tasks

## Use Cases

### Daily Use
- Check system health at a glance
- Trigger updates safely
- Monitor resource usage

### Troubleshooting
- "Internet stopped working" → PrivateManager shows "OPNsense gateway unreachable"
- "AdGuard not blocking" → Shows DNS service down, offers restart button
- "VPN not connecting" → Network diagnostics show firewall rule issue

### Support Interaction
1. Customer has problem
2. Customer clicks "Generate Report" in PrivateManager
3. Report contains: logs, service status, network state, recent changes
4. Customer sends report to support
5. Support can diagnose without remote access or extensive back-and-forth

## Design Goals

**Clarity Over Power**
- Show what customers need, hide technical complexity
- Curated operations, not every possible playbook
- Clear status indicators (up/down, working/broken)

**Diagnostic First**
- Built to help customers help themselves
- Reduces support burden
- Empowers users to understand their system

**Support-Friendly**
- Generate comprehensive diagnostic snapshots
- Standardized report format
- Contains everything support needs to help remotely

**Semaphore as Backbone**
- Don't reinvent automation
- Leverage Semaphore's capabilities
- PrivateManager is UX layer, not logic layer

## What PrivateManager Is NOT

- ❌ Not a Semaphore replacement (sits on top of it)
- ❌ Not running playbooks itself (delegates to Semaphore)
- ❌ Not replacing Homer immediately (may evolve to dashboard later)
- ❌ Not for initial setup (bootstrap handles that)

## Roadmap Position

**Timeline:** Post-FOSS, likely Product Release focus

**Dependencies:**
- Semaphore API capabilities
- Update architecture implementation (for safe updates)
- Service health check framework

**Priority:** High for Product Release (customer support essential)

**Possible FOSS inclusion:** Maybe, if valuable for community and support burden is low

## Success Metrics

**For Customers:**
- Can identify problem without contacting support
- Can safely apply updates without fear
- Clear understanding of system state

**For Support (SubRosa):**
- Reduced support ticket volume
- Faster diagnosis from diagnostic reports
- Fewer "what's your network config?" questions

**For Product:**
- Professional, appliance-like management experience
- Competitive with Firewalla/Ubiquiti UX
- Differentiator: transparency + control

## Open Questions

- Exact technology stack (depends on performance needs)
- Report format and sharing mechanism
- Extent of real-time monitoring vs on-demand checks
- Settings management scope (read-only vs configuration)
- Remote support access method (VPN only, or built-in support tunnel?)
- Mobile-friendly requirements
- Telemetry/privacy considerations for EU customers

## Future Enhancements

Possible evolution beyond initial vision:
- Replace Homer as main dashboard
- Mobile app for iOS/Android
- Push notifications for critical issues
- Automated health reports (weekly emails)
- Integration with vendor support ticketing
- Community forum integration (ask for help with context)

## Notes

This is a **vision document**. Implementation details, technical decisions, and specific features will be designed when PrivateManager development begins.

The goal is to capture the **why** and **what**, not the **how**.
