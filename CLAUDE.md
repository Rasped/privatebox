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

**IMPORTANT**: Context7 is an MCP server that provides up-to-date, version-specific code documentation and examples directly from source libraries. This eliminates outdated or hallucinated code examples by fetching real-time documentation.

### What is Context7?

Context7 is a Model Context Protocol (MCP) server designed to provide:
- Real-time, accurate documentation pulled directly from source libraries
- Version-specific code examples and API references
- Current best practices and implementation patterns
- Support for multiple libraries and frameworks

### How to Use Context7 in Claude Code

1. **Search for Libraries**: Use `mcp__context7__resolve-library-id` to find available documentation
   ```
   Function: mcp__context7__resolve-library-id
   Parameter: libraryName (e.g., "ansible", "react", "fastapi")
   
   Returns: List of matching libraries with:
   - Library ID (Context7-compatible identifier)
   - Name and description
   - Number of code snippets available
   - Trust score (reliability indicator)
   - Available versions (if applicable)
   ```

2. **Load Documentation**: Use `mcp__context7__get-library-docs` with the library ID
   ```
   Function: mcp__context7__get-library-docs
   Parameters:
   - context7CompatibleLibraryID: The exact ID from resolve-library-id
   - tokens: Maximum tokens to retrieve (default: 10000)
   - topic: Optional topic focus (e.g., "hooks", "routing")
   
   Example: Load /ansible/ansible-documentation with 10000 tokens
   ```

### Best Practices for Using Context7

1. **Always Start with Context7**: When working on any technical task, immediately search for and load relevant documentation
2. **Choose Libraries Wisely**: Select libraries based on:
   - **Trust Score**: Prefer scores of 7-10 (more authoritative)
   - **Code Snippets**: More snippets = better coverage
   - **Name Match**: Exact matches are usually best
   - **Version**: Use specific versions if the user mentions them
3. **Load Multiple Sources**: For complex tasks, load documentation from multiple related libraries
4. **Use Topic Filtering**: When you need specific information, use the `topic` parameter to focus results

### Required Documentation for This Project

1. **Ansible Documentation**: 
   ```
   Library ID: /ansible/ansible-documentation
   Trust Score: 9.3
   Code Snippets: 2366
   Description: Core Ansible documentation with comprehensive examples
   ```

2. **Community Proxmox Collection**:
   ```
   Library ID: /ansible-collections/community.proxmox
   Description: Proxmox integration modules for Ansible
   ```

3. **Proxmox VE Documentation**:
   ```
   Library ID: /proxmox/pve-docs
   Trust Score: 8.2
   Code Snippets: 1486
   Description: Official Proxmox VE documentation
   ```

### Example Context7 Workflow

```
User: "Help me create a FastAPI application with authentication"

Claude Code Actions:
1. Search for FastAPI documentation:
   mcp__context7__resolve-library-id("fastapi")
   
2. Load FastAPI docs:
   mcp__context7__get-library-docs("/tiangolo/fastapi", tokens=10000)
   
3. Search for authentication libraries:
   mcp__context7__resolve-library-id("fastapi authentication")
   
4. Load specific auth documentation if found
5. Implement solution using current, accurate examples
```

### Common Technology Library IDs

Here are some commonly used library IDs for quick reference:
- Python: `/context7/python-3.9` (Trust: 10, Snippets: 13580)
- React: Search "react" for latest options
- Node.js: Search "node" or "nodejs"
- Docker: Search "docker"
- Kubernetes: Search "kubernetes"
- AWS: Search "aws" or specific service names

### Troubleshooting Context7

- **"Documentation not found"**: The library might not be finalized. Try searching for alternative names or related libraries
- **Empty results**: Some libraries are listed but not yet populated with documentation
- **Version-specific needs**: If a user needs a specific version, check the `Versions` field in search results

### For Future Agents

When any agent works on this codebase or discusses technical topics:
1. **Immediately search Context7** for relevant documentation before providing any code
2. **Load multiple libraries** if the task involves multiple technologies
3. **Reference loaded documentation** explicitly when implementing features
4. **Update this list** if you discover useful library IDs for this project