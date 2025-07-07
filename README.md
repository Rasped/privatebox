# PrivateBox

## Project Overview

PrivateBox is a **privacy-focused router product** built on Proxmox VE that automates the deployment of privacy-enhancing network services. This repository contains both the bootstrap infrastructure for initial setup and Ansible automation for service deployment.

The project provides a complete solution for setting up a privacy-focused network appliance, including automated VM provisioning, service deployment, and management tools.

## Quick Start

### Installation from GitHub (Recommended)

Run these commands on your Proxmox host to download and execute the installer:

```bash
# Download the installer script
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh

# Run the installer
sudo bash quickstart.sh
```

This will:
- Automatically detect your network configuration
- Create an Ubuntu 24.04 VM on your Proxmox host
- Install Portainer for container management
- Install Semaphore for Ansible automation
- Configure all services and provide access information

### Installation Options

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh

# Run with custom IP address
sudo bash quickstart.sh --ip 192.168.1.50

# Skip network auto-discovery
sudo bash quickstart.sh --no-auto

# Use specific gateway
sudo bash quickstart.sh --ip 192.168.1.50 --gateway 192.168.1.1

# Skip confirmation prompt (unattended)
sudo bash quickstart.sh --yes

# Clean up installation files after completion
sudo bash quickstart.sh --cleanup
```

### Alternative Download Methods

```bash
# Using wget
wget https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh
sudo bash quickstart.sh

# Using curl with different branch
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/develop/quickstart.sh -o quickstart.sh
sudo bash quickstart.sh --branch develop

# Review the script before running
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh
less quickstart.sh  # Review the script
sudo bash quickstart.sh
```

### One-Line Installation (Less Secure)

If you prefer the convenience of a one-line installation:

```bash
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```

**Note:** Piping scripts directly to bash is convenient but less secure. We recommend the two-command approach above.

### What the Quickstart Script Does

1. **Downloads Bootstrap Files**: Fetches the latest bootstrap scripts from GitHub
2. **Runs Network Discovery**: Automatically detects your network configuration
3. **Creates VM**: Provisions an Ubuntu 24.04 VM with optimal settings
4. **Installs Services**: Sets up Portainer and Semaphore via cloud-init
5. **Provides Access Info**: Shows you how to connect to your new PrivateBox

### Troubleshooting

If you can't download from GitHub directly:
```bash
# Use a different branch
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/develop/quickstart.sh | sudo bash

# Check if the script is accessible
curl -I https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh

# View the script before running
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | less
```

## Features

- **Automated VM Provisioning**: One-command setup on Proxmox hosts
- **Network Auto-Discovery**: Automatic detection of network configuration
- **Unattended Installation**: Complete hands-off provisioning
- **Privacy-Focused Services** (via Ansible):
  - OPNSense firewall and router (dedicated VM)
  - AdGuard Home for ad-blocking (containerized)
  - Unbound DNS for enhanced DNS privacy
  - Additional privacy features
- **Management Integration**: Pre-configured Portainer and Semaphore
- **Modular Design**: Reusable Ansible roles for service deployment

## Target Hardware

- Small all-in-one (AIO) computers with Intel N100 CPU and 8-16GB RAM
- Capable of running multiple *nix-based virtual machines for various services

## Repository Structure

```
bootstrap/              # Bootstrap infrastructure and scripts
├── scripts/           # Core installation scripts
│   ├── create-ubuntu-vm.sh    # Main VM creation script
│   ├── network-discovery.sh   # Automatic network detection
│   ├── initial-setup.sh       # Post-install configuration
│   ├── portainer-setup.sh     # Container management setup
│   └── semaphore-setup.sh     # Ansible UI setup
├── config/            # Configuration templates
├── lib/               # Shared libraries
└── deploy-to-server.sh  # Remote deployment tool

docs/                   # Project documentation

quickstart.sh          # One-line installer script
```

## Bootstrap Scripts

- **bootstrap.sh**: Main entry point for complete installation
- **create-ubuntu-vm.sh**: Creates and configures Ubuntu VM on Proxmox
- **network-discovery.sh**: Automatic network configuration detection
- **initial-setup.sh**: Post-install setup (runs via cloud-init)
- **portainer-setup.sh**: Container management UI installation
- **semaphore-setup.sh**: Ansible automation UI installation
- **health-check.sh**: Service health monitoring
- **backup.sh**: Configuration and credential backup

## Planned Ansible Roles

- **common**: Base configuration for all managed systems
- **proxmox**: Manage Proxmox VE host and VM operations
- **opnsense**: Deploy and configure OPNSense firewall
- **adguard_home**: Deploy AdGuard Home DNS filtering
- **unbound_dns**: Deploy Unbound recursive DNS resolver
- **security_hardening**: Apply security best practices

## Getting Started

### Prerequisites

- Proxmox VE 7.0 or higher
- At least 4GB free RAM
- At least 10GB free storage
- Internet connection

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
- Username: `admin`
- Password: Auto-generated during setup (displayed after installation)
- To retrieve manually: `ssh ubuntuadmin@<VM-IP>` then `sudo cat /root/.credentials/semaphore_credentials.txt`

**Note:** The VM credentials above are for logging into the Ubuntu VM, not for Proxmox.

## Security Considerations

- All sensitive variables are encrypted using Ansible Vault
- Dedicated SSH keys for Ansible automation
- Limited API access with proper authentication
- Comprehensive logging for auditing
- Regular rotation of passwords and keys

## Current Status

- ✅ **Bootstrap Infrastructure**: Fully automated VM creation and service deployment
- ✅ **Network Auto-Discovery**: Automatic detection of network configuration
- ✅ **Management Tools**: Portainer and Semaphore pre-installed and configured
- ✅ **Quick Start Script**: One-line installation for easy deployment
- 📋 **Ansible Automation**: To be rebuilt from scratch with simpler approach
- 📋 **Privacy Services**: Planned deployment via Ansible (OPNSense, AdGuard, etc.)

## Next Steps

- Design and implement simple Ansible structure from scratch
- Create basic playbooks for service deployment
- Develop secure secrets and credential management process
- Integrate with existing Semaphore installation
- Test deployment of privacy services (OPNSense, AdGuard, etc.)

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the [LICENSE TYPE] - see the LICENSE file for details.

## Acknowledgments

- Ansible Community
- OPNSense Project
- AdGuard Home Project
- Proxmox VE Team