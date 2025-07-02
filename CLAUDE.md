# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PrivateBox is a privacy-focused router product built on Proxmox, automating deployment of privacy-enhancing services including OPNSense firewall, AdGuard Home, Unbound DNS, and management tools via Ansible.

## Repository Structure

```
ansible/
├── inventories/           # Environment-specific inventory configurations
│   └── development/       # Development environment (currently only environment)
├── roles/                 # Reusable Ansible roles (mostly unimplemented)
│   └── common/           # Basic common role (partially implemented)
└── playbooks/            # Orchestration playbooks
    └── site.yml          # Main site playbook (basic framework only)

documentation/            # Comprehensive planning and technical documentation
```

## Key Architecture Decisions

1. **Target Infrastructure**: Proxmox hypervisor on Intel N100 mini PCs with 8-16GB RAM
2. **Service Architecture**: 
   - OPNSense runs in dedicated VM for performance
   - Other services containerized using Docker/Portainer
   - Semaphore provides web UI for Ansible execution
3. **Network Isolation**: Multiple VLANs for service segregation (planned)

## Development Commands

**Currently no build/test infrastructure exists.** When implementing:

```bash
# Run playbooks (basic execution)
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/site.yml

# Check syntax (when ansible-lint is added)
# ansible-lint ansible/

# Run specific roles
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/site.yml --tags "role_name"
```

## Implementation Status

- **Documentation**: Complete and comprehensive
- **Infrastructure**: Basic directory structure only
- **Roles**: Only `common` role exists with minimal tasks
- **Inventory**: Basic development inventory with placeholder hosts
- **Testing**: Not implemented
- **CI/CD**: Not implemented
- **Secrets Management**: Not implemented

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

1. **Follow Ansible Best Practices**: The project documentation emphasizes idempotency, proper variable scoping, and modular role design
2. **Reference Documentation First**: The documentation/ directory contains extensive planning - check there before implementing new features
3. **Maintain Role Independence**: Each role should be self-contained and reusable
4. **Use Existing Patterns**: When implementing new roles, follow the structure established in the common role

## Key Files to Reference

- `documentation/ansible_technical_implementation_guide.md` - Code examples and patterns
- `documentation/ansible_playbook_organization_plan.md` - Detailed role specifications
- `documentation/planned_ansible_playbooks.md` - List of all playbooks to implement
- `README.md` - Project overview and goals

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