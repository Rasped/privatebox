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
- `semaphore-setup.sh` - Ansible automation UI setup with automatic template synchronization
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
   - Pre-configured with PrivateBox repository
   - Automatic template generation from annotated Ansible playbooks
   - "Generate Templates" task created automatically
   - API token and environment configured for template synchronization

Note: The actual privacy router services (OPNSense, AdGuard Home, Unbound DNS) are deployed via Ansible playbooks from this repository (see the ansible/ directory).

## Mass Production

The `mass-production/` directory contains scripts for automated deployment of multiple PrivateBox machines in a factory/production environment. This includes:

- **client/** - Scripts that run on target machines during provisioning
- **server/** - Management server API (not yet implemented)
- **common.sh** - Shared utilities for mass production scripts

See `mass-production/CLAUDE.md` for detailed documentation.

## Template Synchronization Setup

During bootstrap, `semaphore-setup.sh` automatically configures template synchronization:

### What Bootstrap Does

1. **Creates API Token**: 
   - Authenticates with admin credentials
   - Generates a permanent API token for template operations
   - Saves token to `/root/.credentials/semaphore_credentials.txt`

2. **Creates SemaphoreAPI Environment**:
   - Sets up environment with `SEMAPHORE_URL` and `SEMAPHORE_API_TOKEN`
   - Used by the Python script to connect to Semaphore API

3. **Creates PrivateBox Repository**:
   - Points to the GitHub repository
   - Enables Semaphore to clone and access playbooks

4. **Enables Python Application**:
   - Automatically enabled via `SEMAPHORE_APPS` environment variable
   - No manual UI configuration needed

5. **Creates Generate Templates Task**:
   - Python task that runs `tools/generate-templates.py`
   - Configured with proper inventory, repository, and environment

6. **Runs Initial Sync**:
   - Executes the template generation task
   - Creates templates for any existing annotated playbooks

### Post-Bootstrap Usage

After bootstrap completes:
- Access Semaphore UI at `http://<VM-IP>:3000`
- Find "Generate Templates" task in the PrivateBox project
- Run it manually to sync new or updated playbooks
- Templates are created/updated based on `semaphore_*` metadata in playbooks

### Troubleshooting

If template sync fails:
- Check Semaphore logs: `podman logs semaphore-ui`
- Verify API token is valid in `/root/.credentials/semaphore_credentials.txt`
- Ensure "Default Inventory" and "PrivateBox" repository exist in Semaphore
- Check Python script output in task execution history