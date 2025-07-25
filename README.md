# PrivateBox

Your privacy-focused network appliance - automated deployment of privacy-enhancing services on Proxmox VE.

## What is PrivateBox?

PrivateBox transforms a mini PC running Proxmox into a comprehensive privacy protection system for your network. It automatically deploys and manages services like ad-blocking, secure DNS, and firewall protection with just one command.

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
- Create a management VM with all tools pre-installed
- Set up web interfaces for easy management
- Display connection information when complete

### Custom Installation

```bash
# Specify IP address
sudo bash quickstart.sh --ip 192.168.1.50

# Specify gateway
sudo bash quickstart.sh --ip 192.168.1.50 --gateway 192.168.1.1

# Skip network auto-discovery
sudo bash quickstart.sh --no-auto --ip 192.168.1.50 --gateway 192.168.1.1

# Unattended installation
sudo bash quickstart.sh --yes

# Clean up installation files after completion
sudo bash quickstart.sh --cleanup

# See all options
sudo bash quickstart.sh --help
```

## What's Included

### Privacy Services
- **AdGuard Home**: Network-wide ad and tracker blocking
- **OPNsense**: Enterprise-grade firewall and router (coming soon)
- **Unbound DNS**: Privacy-focused recursive DNS resolver (coming soon)

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

## Getting Started

### Manual Installation

If you prefer to run the bootstrap scripts manually:

```bash
# Clone the repository
git clone https://github.com/Rasped/privatebox.git
cd privatebox/bootstrap

# Run with auto-discovery (recommended)
sudo ./bootstrap.sh

# Or run with specific network settings
sudo ./scripts/create-ubuntu-vm.sh --ip 192.168.1.50 --gateway 192.168.1.1
```

### Remote Deployment

Deploy to a remote Proxmox server:

```bash
# Deploy and run bootstrap
./bootstrap/deploy-to-server.sh 192.168.1.10

# Deploy with testing
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test
```

### Access Information

After installation completes (5-10 minutes), you can access your PrivateBox VM:

**VM Login Credentials:**
- SSH: `ssh ubuntuadmin@<VM-IP>`
- Username: `ubuntuadmin`
- Password: `Changeme123` (⚠️ change immediately after first login!)

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
```

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

### ✅ Phase 0: Prerequisites & Information Gathering (2025-07-24)
**Successfully completed all Phase 0 objectives:**
- **VM Hostname Resolution**: Fixed cloud-init configuration to prevent "sudo: unable to resolve host" errors
- **Podman Quadlet Networking**: Documented container binding behavior (binds to VM IP, not localhost)
- **AdGuard API Documentation**: Created comprehensive test scripts and documented all API endpoints
- **100% Hands-Off Deployment**: AdGuard now deploys and configures automatically via Ansible
- **Health Check Fix**: Updated to use VM IP address instead of localhost
- **Automatic Configuration**: Integrated AdGuard setup into main playbook with proper port handling
- **DNS Integration**: System automatically uses AdGuard for DNS after deployment

### ✅ Fully Automated Bootstrap (2025-07-21)
- **100% Hands-Off Deployment**: Complete automation from start to finish (~3 minutes)
- **Network Auto-Discovery**: Automatic detection and configuration of network settings
- **Management Tools**: Portainer and Semaphore automatically installed and configured
- **Template Synchronization**: All service templates generated automatically from playbook metadata
- **Quick Start Script**: One-line installation with full automation
- **SSH Key Management**: VM can self-manage via Ansible with proper authorization
- **API Integration**: Simplified authentication with JSON-safe password generation

### 🚧 In Progress
- **Phase 1 Network Architecture**: Ready to implement OPNsense and network segmentation
- **SSH Authentication**: Resolving Ansible SSH access from Semaphore (tracked separately)
- **Additional Services**: OPNSense, Unbound DNS, and other privacy services planned

### 📋 Planned
- **Secrets Management**: Secure handling of credentials and sensitive data
- **Multi-VLAN Support**: Network segregation for enhanced security
- **Backup/Restore**: Automated configuration backup and recovery

## Next Steps

- Begin Phase 1: Implement OPNsense VM creation and network architecture
- Resolve SSH authentication issue for Ansible playbook execution from Semaphore
- Deploy additional privacy services (Unbound DNS, VPN services)
- Implement secure secrets management with Ansible Vault
- Create monitoring and health check dashboards
- Document production deployment best practices

## Where to Find More

For more detailed information:

- **Technical Bootstrap Details**: See [bootstrap/README.md](bootstrap/README.md) for in-depth installation documentation
- **Development Information**: See [CLAUDE.md](CLAUDE.md) for architecture decisions and development guidelines  
- **Service Documentation**: Check [documentation/](documentation/) for deployment guides and technical references

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the [LICENSE TYPE] - see the LICENSE file for details.

## Acknowledgments

- Ansible Community
- OPNSense Project
- AdGuard Home Project
- Proxmox VE Team