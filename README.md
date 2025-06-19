# PrivateBox Ansible

## Project Overview

PrivateBox Ansible is a collection of Ansible playbooks and roles designed to automate the deployment and configuration of a **privacy-focused router product**. This repository contains **only the Ansible automation components** of the larger PrivateBox project.

This component provides systematic automation for setting up, configuring, and managing virtual machines and infrastructure components that deliver privacy-enhancing network services. The actual service configurations, VM templates, and other non-Ansible components are maintained in separate repositories of the PrivateBox project.

## Features

- **Automated VM Provisioning**: Streamlined creation and configuration of VMs on Proxmox hosts
- **Unattended Installations**: Hands-off provisioning of operating systems and services
- **Privacy-Focused Services**:
  - OPNSense firewall and router (dedicated VM)
  - AdGuard Home for ad-blocking (containerized)
  - Unbound DNS for enhanced DNS privacy
  - Additional privacy features
- **Management Integration**: Seamless integration with Portainer, Proxmox, and Semaphore
- **Modular Design**: Reusable Ansible roles and playbooks for flexibility and maintainability

## Target Hardware

- Small all-in-one (AIO) computers with Intel N100 CPU and 8-16GB RAM
- Capable of running multiple *nix-based virtual machines for various services

## Repository Structure

```
ansible/
├── inventories/        # Environment-specific inventory files
├── roles/              # Modular, reusable Ansible roles
├── playbooks/          # Orchestration, deployment, and maintenance playbooks
├── collections/        # External collection dependencies
├── group_vars/         # Group-specific variables
├── host_vars/          # Host-specific variables
├── vault/              # Encrypted secrets
├── templates/          # Jinja2 templates
├── files/              # Static files for deployment
└── ansible.cfg         # Ansible configuration
```

## Primary Roles

- **common**: Base configuration for all managed systems
- **proxmox**: Manage Proxmox VE host and VM operations
- **opnsense**: Deploy and configure OPNSense firewall
- **adguard_home**: Deploy AdGuard Home DNS filtering
- **unbound_dns**: Deploy Unbound recursive DNS resolver
- **portainer**: Manage Portainer container management platform
- **semaphore**: Deploy and configure Semaphore UI for Ansible
- **security_hardening**: Apply security best practices across systems

## Key Playbooks

1. **site.yml**: Complete infrastructure deployment orchestration
2. **provision_infrastructure.yml**: VM provisioning on Proxmox hosts
3. **deploy_base_services.yml**: Common configuration across all systems
4. **deploy_network_services.yml**: Networking and security services
5. **deploy_management_services.yml**: Management tools deployment
6. **maintenance.yml**: Regular system maintenance tasks
7. **backup.yml**: Configuration backup procedures

## Getting Started

### Prerequisites

- Proxmox host configured with API access
- SSH access to target hosts
- Ansible 2.10+ installed on control node
- Required Ansible collections:
  - community.general
  - containers.podman
  - community.crypto
  - ansible.posix

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/privatebox-ansible.git
   cd privatebox-ansible
   ```

2. Install required Ansible collections:
   ```bash
   ansible-galaxy collection install -r collections/requirements.yml
   ```

3. Configure inventory files in the `inventories/` directory
   - Update host information
   - Set environment-specific variables

4. Create and encrypt necessary secrets:
   ```bash
   ansible-vault create group_vars/vault/all.yml
   ```

5. Run the deployment:
   ```bash
   ansible-playbook -i inventories/production playbooks/site.yml
   ```

## Security Considerations

- All sensitive variables are encrypted using Ansible Vault
- Dedicated SSH keys for Ansible automation
- Limited API access with proper authentication
- Comprehensive logging for auditing
- Regular rotation of passwords and keys

## Current Status

- Initial machine setup is nearly fully automated
- Directory structure and playbook organization plan completed
- Implementation of roles and playbooks in progress
- Integration with Semaphore planned for execution management

## Next Steps

- Develop secure secrets and credential management process
- Implement reusable Ansible roles for all required services
- Integrate dynamic inventory with Proxmox
- Establish backup and disaster recovery strategies
- Create playbook testing processes and documentation

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the [LICENSE TYPE] - see the LICENSE file for details.

## Acknowledgments

- Ansible Community
- OPNSense Project
- AdGuard Home Project
- Proxmox VE Team