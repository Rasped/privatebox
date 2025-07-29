# PrivateBox Architecture

## Overview

PrivateBox uses a pragmatic, two-phase approach to create a privacy-focused network appliance:

1. **Bootstrap Phase**: Bash scripts create the initial infrastructure
2. **Service Deployment Phase**: Ansible playbooks deploy containerized services

## Design Philosophy

### Why This Approach?

- **Bootstrap via Bash**: When starting from a fresh Proxmox installation, there's no Ansible controller yet. Bash scripts are the only option.
- **Service-Oriented Ansible**: Once the management VM exists, we use simple, dedicated playbooks for each service rather than complex role hierarchies.
- **SSH over API**: We use SSH access to the Proxmox host for VM creation, avoiding API complexity and credentials management.
- **Containers via Podman**: Services run as systemd-managed containers using Podman Quadlet for better integration.

## Architecture Components

### 1. Bootstrap Infrastructure (Bash)

The bootstrap process runs directly on the Proxmox host:

```
quickstart.sh
    ↓ (downloads)
bootstrap/
├── bootstrap.sh          # Main orchestrator
├── scripts/
│   ├── create-ubuntu-vm.sh     # Creates management VM
│   ├── network-discovery.sh    # Auto-detects network
│   ├── initial-setup.sh        # Runs inside VM via cloud-init
│   ├── portainer-setup.sh      # Container management UI
│   └── semaphore-setup.sh      # Ansible UI with auto-sync
└── lib/
    ├── common.sh         # Shared functions
    └── validation.sh     # Input validation
```

**Key Features:**
- One-line installation from GitHub
- Automatic network configuration detection
- Cloud-init for unattended VM setup
- Pre-configured Portainer and Semaphore

### 2. Service Deployment (Ansible)

Once the management VM is running, Ansible takes over:

```
ansible/
├── inventories/development/    # Target hosts (VMs)
├── group_vars/all.yml         # Common configuration
└── playbooks/services/        # Service deployments
    ├── deploy-adguard.yml     # AdGuard Home
    ├── deploy-unbound.yml     # DNS resolver (planned)
    └── deploy-opnsense.yml    # Firewall VM (planned)
```

**Key Features:**
- One playbook per service (simple to understand)
- Semaphore UI templates auto-generated from playbook metadata
- Podman Quadlet for systemd-native container management
- SSH-based VM creation for OPNSense

## Service Architecture

### Container Services (Podman)

Most services run as containers managed by systemd:

```yaml
# Example: AdGuard Home
/etc/containers/systemd/
└── adguard.container    # Quadlet unit file
    ↓ (systemd generates)
systemd service: adguard.service
```

Benefits:
- Native systemd integration
- Automatic restarts
- Log management via journald
- Resource limits via systemd

### VM Services (OPNSense)

Performance-critical services run in dedicated VMs:

```yaml
# Created via SSH to Proxmox host
qm create 201 --name opnsense-router ...
qm set 201 --net0 virtio,bridge=vmbr0 ...
```

## Workflow Example

### 1. Initial Setup

```bash
# On fresh Proxmox host
curl -fsSL https://raw.githubusercontent.com/.../quickstart.sh | sudo bash
```

This creates:
- Ubuntu 24.04 management VM
- Portainer on port 9000
- Semaphore on port 3000
- Auto-configured network settings

### 2. Service Deployment

```bash
# From Semaphore UI or CLI
ansible-playbook -i inventories/development/hosts.yml \
    playbooks/services/deploy-adguard.yml
```

This:
- Connects to management VM via SSH
- Creates Podman Quadlet configuration
- Starts service via systemd
- Configures health checks

## Key Design Decisions

### 1. No Proxmox API

**Decision**: Use SSH commands instead of Proxmox API
**Rationale**: 
- Simpler authentication (SSH keys already needed)
- No API credentials to manage
- Direct, understandable commands
- Works with any Proxmox version

### 2. Service-Oriented Playbooks

**Decision**: One playbook per service, no complex roles
**Rationale**:
- Maps 1:1 with Semaphore job templates
- Easy to understand and debug
- Simple to add new services
- Slight duplication worth the clarity

### 3. Podman Over Docker

**Decision**: Use Podman with Quadlet
**Rationale**:
- Better systemd integration
- Rootless containers possible
- No daemon required
- Quadlet provides declarative config

### 4. Bash Bootstrap

**Decision**: Keep bootstrap in bash, not Ansible
**Rationale**:
- No Ansible controller exists initially
- Must work on minimal Proxmox install
- Simple, auditable scripts
- Cloud-init handles complexity

## Adding New Services

### For Container Services:

1. Create playbook: `ansible/playbooks/services/deploy-[service].yml`
2. Add Semaphore metadata to vars_prompt
3. Create Quadlet template if needed
4. Test deployment
5. Run template sync to update Semaphore

### For VM Services:

1. Create playbook using SSH commands to Proxmox
2. Use existing VM as template if possible
3. Configure networking via Proxmox CLI
4. Add post-deployment configuration

## Security Considerations

- SSH key authentication only (no passwords)
- Services isolated in containers/VMs  
- Firewall rules before service deployment
- Secrets management (TODO: implement Ansible Vault)
- Minimal attack surface

## Future Enhancements

1. **Backup/Restore**: Automated configuration backups
2. **Monitoring**: Prometheus/Grafana stack
3. **Updates**: Automated security updates
4. **Multi-Site**: Support for multiple Proxmox clusters