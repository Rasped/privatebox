# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PrivateBox is a privacy-focused router product built on Proxmox VE. The project provides automated bootstrap infrastructure for VM creation and service deployment, with planned Ansible automation for privacy-enhancing services including OPNSense firewall, AdGuard Home, and Unbound DNS.

## Repository Structure

```
bootstrap/                 # Bootstrap infrastructure (FULLY IMPLEMENTED)
├── scripts/              # Core installation scripts
│   ├── create-ubuntu-vm.sh      # Main VM creation with cloud-init
│   ├── network-discovery.sh     # Automatic network configuration
│   ├── initial-setup.sh         # Post-install setup (via cloud-init)
│   ├── portainer-setup.sh       # Container management installation
│   ├── semaphore-setup.sh       # Ansible UI installation
│   ├── fix-proxmox-repos.sh     # Proxmox repository fixes
│   ├── health-check.sh          # Service health monitoring
│   └── backup.sh               # Configuration backup
├── config/               # Configuration templates
│   └── privatebox.conf.example  # Example configuration
├── lib/                  # Shared libraries
│   ├── common.sh               # Common functions
│   └── validation.sh           # Input validation
├── deploy-to-server.sh   # Remote deployment tool
└── bootstrap.sh          # Main entry point

quickstart.sh             # One-line installer (downloads and runs bootstrap)

ansible/                  # Ansible automation (PARTIALLY IMPLEMENTED)
├── inventories/          # Environment-specific inventory configurations
│   └── development/      # Development environment
├── roles/                # Reusable Ansible roles (mostly unimplemented)
│   └── common/          # Basic common role (partially implemented)
└── playbooks/           # Orchestration playbooks
    └── site.yml         # Main site playbook (basic framework only)

documentation/           # Comprehensive planning and technical documentation
```

## Key Architecture Decisions

1. **Target Infrastructure**: Proxmox VE on Intel N100 mini PCs with 8-16GB RAM
2. **Bootstrap Architecture**:
   - Ubuntu 24.04 LTS VM as management host
   - Cloud-init for unattended installation
   - Automatic network configuration detection
   - Pre-installed Portainer and Semaphore
3. **Service Architecture** (Planned via Ansible): 
   - OPNSense runs in dedicated VM for performance
   - Other services containerized using Docker/Portainer
   - Semaphore provides web UI for Ansible execution
4. **Network Features**:
   - Automatic IP detection and assignment
   - Support for static IP configuration
   - Multiple VLANs for service segregation (planned)

## Development Commands

### Quick Start (One-Line Installation)

```bash
# Basic installation with auto-discovery
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash

# With custom IP
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash -s -- --ip 192.168.1.50

# Skip confirmation prompt
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash -s -- --yes
```

### Bootstrap Commands

```bash
# Run complete bootstrap with auto-discovery
sudo ./bootstrap/bootstrap.sh

# Create VM with specific network settings
sudo ./bootstrap/scripts/create-ubuntu-vm.sh --ip 192.168.1.50 --gateway 192.168.1.1

# Test network discovery
sudo ./bootstrap/scripts/network-discovery.sh

# Deploy to remote server
./bootstrap/deploy-to-server.sh 192.168.1.10 root

# Deploy and run tests
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test

# Check service health
ssh privatebox@<VM-IP> 'sudo /opt/privatebox/scripts/health-check.sh'
```

### Ansible Commands (Future)

```bash
# Run playbooks (when implemented)
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/site.yml

# Run specific roles
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/site.yml --tags "role_name"
```

## Implementation Status

### Bootstrap (COMPLETE)
- ✅ **Quick Start Script**: One-line installer with auto-discovery
- ✅ **VM Creation**: Automated Ubuntu 24.04 VM provisioning
- ✅ **Network Discovery**: Automatic network configuration detection
- ✅ **Service Installation**: Portainer and Semaphore auto-installed
- ✅ **Cloud-Init**: Unattended setup via cloud-init
- ✅ **Remote Deployment**: Deploy to remote Proxmox servers
- ✅ **Health Monitoring**: Service health check scripts

### Ansible (IN PROGRESS)
- ✅ **Documentation**: Complete and comprehensive
- 🚧 **Infrastructure**: Basic directory structure only
- 🚧 **Roles**: Only `common` role exists with minimal tasks
- 🚧 **Inventory**: Basic development inventory with placeholder hosts
- ❌ **Testing**: Not implemented
- ❌ **CI/CD**: Not implemented
- ❌ **Secrets Management**: Not implemented

## Critical Implementation Notes

1. **Planned Roles** (from documentation/ansible_playbook_organization_plan.md):
   - proxmox: VM/container provisioning
   - opnsense: Firewall configuration
   - adguard_home: DNS filtering setup
   - unbound_dns: Recursive DNS resolver
   - portainer: Container management
   - semaphore: Ansible UI
   - security_hardening: System security

2. **Dynamic Inventory**: Plan to integrate with Proxmox API for automatic host discovery

3. **Secrets Management**: Needs implementation before any real deployment

4. **Testing Strategy**: Molecule tests planned for each role

## When Working on This Project

### Bootstrap Development

1. **Test Network Discovery First**: Always verify network detection works in the target environment
2. **Use Common Libraries**: Source `lib/common.sh` for logging and utility functions
3. **Maintain Idempotency**: Bootstrap scripts should be safe to run multiple times
4. **Check Prerequisites**: Always verify Proxmox environment before proceeding
5. **Follow Cloud-Init Best Practices**: Keep cloud-init configs simple and reliable

### Ansible Development

1. **Follow Ansible Best Practices**: The project documentation emphasizes idempotency, proper variable scoping, and modular role design
2. **Reference Documentation First**: The documentation/ directory contains extensive planning - check there before implementing new features
3. **Maintain Role Independence**: Each role should be self-contained and reusable
4. **Use Existing Patterns**: When implementing new roles, follow the structure established in the common role

## Key Files to Reference

### Bootstrap Files
- `quickstart.sh` - One-line installer script
- `bootstrap/bootstrap.sh` - Main bootstrap entry point
- `bootstrap/scripts/create-ubuntu-vm.sh` - Core VM creation logic
- `bootstrap/scripts/network-discovery.sh` - Network auto-detection
- `bootstrap/config/privatebox.conf.example` - Configuration template
- `bootstrap/README.md` - Bootstrap documentation

### Ansible Documentation
- `documentation/ansible_technical_implementation_guide.md` - Code examples and patterns
- `documentation/ansible_playbook_organization_plan.md` - Detailed role specifications
- `documentation/planned_ansible_playbooks.md` - List of all playbooks to implement
- `README.md` - Project overview and quick start guide

## Context7 Documentation Loading

**IMPORTANT**: When working on this project or any technical subject, ALWAYS load relevant documentation using Context7 MCP tools at the start of the conversation.

### Required Documentation for This Project

1. **Ansible Documentation**: 
   ```
   Library ID: /ansible/ansible-documentation
   Description: Core Ansible documentation with 2362 code snippets
   ```

2. **Community Proxmox Collection**:
   ```
   Library ID: /ansible-collections/community.proxmox
   Description: Proxmox integration for Ansible
   ```

### How to Use Context7

1. **Search for Libraries**: Use `mcp__context7__resolve-library-id` with a library name to find available documentation
   ```
   Example: Search for "ansible" to find Ansible-related libraries
   ```

2. **Load Documentation**: Use `mcp__context7__get-library-docs` with the Context7-compatible library ID
   ```
   Example: Load /ansible/ansible-documentation with 10000 tokens
   ```

### General Context7 Guidelines

- **Always use Context7** when working with any technology or framework
- **Search first** if you don't know the exact library ID
- **Load documentation proactively** at the start of conversations
- **Prefer libraries with**:
  - Higher trust scores (7-10)
  - More code snippets
  - Exact name matches
  - Recent versions if available

### For Future Agents

When any agent works on this codebase or discusses technical topics:
1. Immediately check if Context7 has relevant documentation
2. Load appropriate libraries before starting work
3. Reference the loaded documentation when implementing features
4. If working with a new technology, search Context7 first