# PrivateBox

Your privacy-focused network appliance - automated deployment of privacy-enhancing services on Proxmox VE.

## What is PrivateBox?

PrivateBox transforms a mini PC running Proxmox into a comprehensive privacy protection system for your network. It automatically deploys and manages services like ad-blocking and secure DNS with just one command.

**Key Features:**

- 🛡️ **Privacy Protection**: Ad-blocking, DNS privacy, and firewall in one solution
- 🚀 **One-Command Setup**: Fully automated deployment in ~5 minutes
- 🎯 **Service-Oriented**: Clean, modular architecture for each service
- 🔧 **Web Management**: Built-in UIs for container and automation management
- 📦 **Minimal Hardware**: Runs on Intel N100 mini PCs with 8GB RAM

## Quick Start

Run this command on your Proxmox host:

```bash
# Review the script before running (recommended)
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh
less quickstart.sh  # Review the script
sudo bash quickstart.sh

# Or run directly if you trust the source
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```

That's it! The installer will:

- Detect your network configuration automatically
- Create a management VM (Debian 12 by default) with all tools pre-installed
- Set up web interfaces for easy management
- Display connection information when complete

### Custom Installation

```bash

# Unattended installation
sudo bash quickstart.sh --yes

# Clean up installation files after completion
sudo bash quickstart.sh --cleanup

# See all options
sudo bash quickstart.sh --help
```

## What's Included

### Privacy Services

- **AdGuard Home**: Network-wide ad and tracker blocking (Available)
- **OPNsense**: Enterprise-grade firewall and router (Planned - In Development)
- **Unbound DNS**: Privacy-focused recursive DNS resolver (Planned)

### Management Tools

- **Portainer**: Simple container management with web UI
- **Semaphore**: Ansible automation with point-and-click deployment

## Prerequisites

- Proxmox VE 7.0 or higher
- Intel N100 mini PC (or similar) with 8GB+ RAM
- 20GB available storage
- Internet connection

## Repository Structure

```
bootstrap/       # Installation scripts and infrastructure
ansible/         # Service deployment playbooks
documentation/   # Technical documentation and guides
```

## Current Deployment Status

**✅ 100% Hands-off Deployment Achieved!** See [DEPLOYMENT-STATUS.md](documentation/DEPLOYMENT-STATUS.md) for detailed status report.

## Getting Started

````

### Access Information

After installation completes (5-10 minutes), you can access your PrivateBox VM:


**Web Services** (available after VM login):
- **Portainer**: `http://<VM-IP>:9000` - Container management UI
- **Semaphore**: `http://<VM-IP>:3000` - Ansible automation UI

**Semaphore Login:**
- Username: `ubuntuadmin`
- Password: Auto-generated during setup (displayed after installation)
- To retrieve manually: `ssh ubuntuadmin@<VM-IP>` then `sudo cat /root/.credentials/semaphore_credentials.txt`

**Semaphore Template Synchronization:**
- Bootstrap automatically creates a "Generate Templates" task in Semaphore
- Ansible playbooks with `semaphore_*` metadata in `vars_prompt` are automatically synced to Semaphore job templates
- Run "Generate Templates" from Semaphore UI to sync new or updated playbooks
- Initial sync runs automatically during bootstrap setup

**Note:** The VM credentials above are for logging into the Ubuntu VM, not for Proxmox.

## Template Synchronization

PrivateBox includes automatic template synchronization that eliminates manual template creation in Semaphore:

### How It Works

1. **Annotate Playbooks**: Add `semaphore_*` fields to `vars_prompt` in your Ansible playbooks
2. **Automatic Setup**: Bootstrap creates all necessary infrastructure:
   - Generates API token for template operations
   - Creates SemaphoreAPI environment with credentials
   - Sets up PrivateBox repository in Semaphore
   - Creates "Generate Templates" Python task
   - Runs initial synchronization automatically
3. **Sync Process**: The Python script (`tools/generate-templates.py`):
   - Scans `ansible/playbooks/services/*.yml` for playbooks with metadata
   - Creates or updates Semaphore templates based on the metadata
   - Converts variable types appropriately (boolean → enum, integer → int)
   - Shows default values in description fields

### Example Annotated Playbook

```yaml
vars_prompt:
  - name: service_enabled
    prompt: "Enable the service?"
    default: "yes"
    private: no
    # Semaphore template metadata
    semaphore_type: boolean
    semaphore_description: "Enable or disable the service"

  - name: port_number
    prompt: "Service port"
    default: "8080"
    semaphore_type: integer
    semaphore_min: 1024
    semaphore_max: 65535
````

### Running Template Sync

- **Initial Sync**: Runs automatically during bootstrap
- **Manual Sync**: Click "Run" on "Generate Templates" task in Semaphore UI
- **What Happens**: Templates are created/updated for all annotated playbooks

## Security Considerations

- All sensitive variables are encrypted using Ansible Vault
- Dedicated SSH keys for Ansible automation
- Limited API access with proper authentication
- Comprehensive logging for auditing
- Regular rotation of passwords and keys

## Current Status

### ✅ Working Features

- **Bootstrap System**: One-command VM creation with all management tools
- **Container Management**: Portainer for easy container administration
- **Automation Platform**: Semaphore with automatic template synchronization
- **AdGuard Home**: Fully automated deployment via Semaphore templates
- **SSH Key Management**: Automatic configuration for both Proxmox and container hosts

### 🚧 In Development

- **OPNsense Integration**: Firewall and router functionality
- **Network Segmentation**: VLAN-based network isolation (design phase)
- **Additional Privacy Services**: Unbound DNS, WireGuard VPN

### 📋 Future Features

- **Consumer Dashboard**: User-friendly web interface for non-technical users
- **Backup/Restore**: Automated configuration backup and recovery
- **Additional Services**: Pi-hole, WireGuard VPN, Nginx Proxy Manager

## Documentation

For more detailed information:

- **Bootstrap Details**: See [bootstrap/README.md](bootstrap/README.md) for technical installation documentation
- **Service Deployment**: See [ansible/README.md](ansible/README.md) for service deployment via Semaphore
- **Development Guide**: See [CLAUDE.md](CLAUDE.md) for contributing and development guidelines

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the [LICENSE TYPE] - see the LICENSE file for details.

## Acknowledgments

- Ansible Community
- OPNSense Project
- AdGuard Home Project
- Proxmox VE Team
