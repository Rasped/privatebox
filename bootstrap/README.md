# PrivateBox Bootstrap Module

Self-contained bootstrap scripts for setting up PrivateBox infrastructure on Proxmox VE.

## Quick Start

```bash
# Fix Proxmox repositories (if needed)
sudo ./scripts/fix-proxmox-repos.sh

# Create Ubuntu VM with all services
sudo ./scripts/create-ubuntu-vm.sh

# Or use automatic network discovery
sudo ./scripts/create-ubuntu-vm.sh --auto-discover
```

## Remote Deployment

Deploy and test PrivateBox on a remote Proxmox server:

```bash
# Deploy to remote server
./deploy-to-server.sh 192.168.1.10

# Deploy and run integration tests
./deploy-to-server.sh 192.168.1.10 root --test

# Deploy without executing bootstrap (manual run later)
./deploy-to-server.sh 192.168.1.10 root --no-execute

# Deploy, test, and cleanup
./deploy-to-server.sh 192.168.1.10 root --test --cleanup
```

## Scripts

- `create-ubuntu-vm.sh` - Creates Ubuntu 24.04 VM on Proxmox with cloud-init
- `deploy-to-server.sh` - Deploy bootstrap to remote server and run tests
- `network-discovery.sh` - Automatic network configuration discovery
- `initial-setup.sh` - Post-install setup (runs automatically via cloud-init)
- `portainer-setup.sh` - Container management UI setup
- `semaphore-setup.sh` - Ansible automation UI setup
- `fix-proxmox-repos.sh` - Fixes Proxmox repository configuration
- `backup.sh` - Backup utility for configurations and credentials
- `health-check.sh` - Service health monitoring

## Configuration

Edit `config/privatebox.conf` to customize:
- VM specifications (CPU, RAM, storage)
- Network settings (IP, gateway, bridge)
- Credentials (username, password)
- Service ports

Or use `--auto-discover` to automatically detect network settings and generate the configuration file.

## Directory Structure

```
bootstrap/
├── scripts/         # All bootstrap scripts
├── lib/            # Common functions library
├── config/         # Configuration files
└── mass-production/ # Mass production deployment (client/server)
```

## Dependencies

- Proxmox VE host
- Internet connectivity for package downloads
- Sufficient resources (4GB RAM, 2 CPUs minimum)

## Services Deployed

1. **Portainer** - Docker/Podman container management (port 9000)
2. **Semaphore** - Ansible automation UI (port 3000)

Note: The actual privacy router services (OPNSense, AdGuard Home, Unbound DNS) are deployed via Ansible playbooks from this repository (see the ansible/ directory).

## Mass Production

The `mass-production/` directory contains scripts for automated deployment of multiple PrivateBox machines in a factory/production environment. This includes:

- **client/** - Scripts that run on target machines during provisioning
- **server/** - Management server API (not yet implemented)
- **common.sh** - Shared utilities for mass production scripts

See `mass-production/CLAUDE.md` for detailed documentation.