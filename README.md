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
bash quickstart.sh

# Or run directly if you trust the source
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash
```

That's it! The installer will:

- Detect your network configuration automatically
- Create a management VM (Debian 13) with all tools pre-installed
- Set up web interfaces for easy management
- Display connection information when complete

### Installation Options

```bash
# Dry run (test without creating VM)
bash quickstart.sh --dry-run

# Keep downloaded files after installation
bash quickstart.sh --no-cleanup

# Use specific git branch
bash quickstart.sh --branch develop

# Verbose output
bash quickstart.sh --verbose

# See all options
bash quickstart.sh --help
```

## What's Included

### Privacy Services

- **AdGuard Home**: Network-wide ad and tracker blocking with DNS filtering
- **OPNsense**: Enterprise-grade firewall and router with VLAN support
- **Headscale**: Self-hosted VPN control plane (Tailscale-compatible)

### Management Tools

- **Portainer**: Container management with web UI
- **Semaphore**: Ansible automation platform with web UI
- **Homer**: Centralized dashboard for all services

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

## Access Information

After installation completes (~15 minutes), you can access your PrivateBox services using `.lan` domains with HTTPS and self-signed certificates:

**Network Services:**
- **AdGuard Home**: `https://adguard.lan` - DNS filtering and ad blocking
- **OPNsense**: `https://opnsense.lan` - Firewall and router management
- **Headplane**: `https://headplane.lan/admin` - VPN management

**Management Services:**
- **Portainer**: `https://portainer.lan` - Container management UI
- **Semaphore**: `https://semaphore.lan` - Ansible automation UI
- **Proxmox**: `https://proxmox.lan` - Virtualization platform

**Dashboard:**
- **Homer**: `https://homer.lan` - Central dashboard for all services

**Login Credentials:**
- Username: `admin`
- Password: Auto-generated during setup (displayed after installation)
- To retrieve: `ssh debian@<VM-IP>` then `sudo cat /etc/privatebox/config.env | grep SERVICES_PASSWORD`

**Certificate Warnings:**
- First visit: Browser shows security warning (self-signed certificate)
- Click "Advanced" → "Proceed" to accept
- This is normal for network appliances (same as UniFi, Firewalla, pfSense)

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

## Security Features

- Auto-generated unique passwords per installation
- Dedicated SSH keys for automation
- HTTPS for all management interfaces
- VLAN-based network segmentation
- API access with authentication tokens

## Deployment Status

### ✅ Complete & Working

- **Automated Bootstrap**: One-command deployment on Proxmox
- **Network Infrastructure**: OPNsense firewall with VLAN segmentation
- **DNS & Ad-Blocking**: AdGuard Home with custom blocklists
- **VPN Infrastructure**: Headscale (Tailscale-compatible) with Headplane UI
- **Container Platform**: Portainer for service management
- **Automation**: Semaphore with automatic template generation
- **Service Dashboard**: Homer with all service links
- **HTTPS**: Self-signed certificates for all services

### 🚧 In Progress

- **Documentation**: End-user guides and troubleshooting

### 📋 Planned

- **Recovery System**: Factory reset and disaster recovery mechanisms
- **Backup/Restore**: Automated configuration backup

## Documentation

For more detailed information:

- **Bootstrap Details**: See [bootstrap/README.md](bootstrap/README.md) for technical installation documentation
- **Service Deployment**: See [ansible/README.md](ansible/README.md) for service deployment via Semaphore
- **Development Guide**: See [CLAUDE.md](CLAUDE.md) for contributing and development guidelines

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the EUPL - see the LICENSE file for details.

## Acknowledgments

- Ansible Community
- OPNSense Project
- AdGuard Home Project
- Proxmox VE Team
