# Project Overview

The primary goal of this project is to deliver a **privacy-focused router product**. To achieve this, the project focuses on automating and streamlining the setup, configuration, and management of virtual machines and related infrastructure components. This product will feature services such as OPNSense (running in its own VM) for firewall and routing, AdGuard Home (running in a container) for ad-blocking, and Unbound DNS for enhanced privacy, with other privacy features also planned. The automation aspect includes provisioning, unattended installations, and integration with tools such as Portainer, Proxmox, and Semaphore for efficient orchestration and monitoring.

## Overall Goal
Automate and streamline the setup, configuration, and management of virtual machines and related infrastructure components to support the delivery of the privacy-focused router product. This includes provisioning, unattended installations, and integration with tools such as Portainer, Proxmox, and Semaphore for efficient orchestration and monitoring.

## Target Hardware
- The primary hardware is a small all-in-one (AIO) computer, typically equipped with an Intel N100 CPU and 8-16GB of RAM.
- Each device will run multiple *nix-based virtual machines to provide various privacy and networking services.

## Project Details
- **Automated VM Setup:** Scripts automate the creation and configuration of VMs, reducing manual intervention and ensuring consistency.
- **Unattended Installations:** Mechanisms for unattended OS installations enable rapid, hands-off provisioning.
- **Integration with Management Tools:** Integration with Portainer, Proxmox, and Semaphore for centralized management.
- **Ansible Automation:** Ansible playbooks will be the primary method for post-setup configuration and management, executed and managed through Semaphore. Playbooks will be organized for reusability and shared via a Git repository.
- **Dynamic Inventory:** Plans to use dynamic inventory, likely integrated with Proxmox, to manage VM targets for Ansible.
- **Secrets Management:** No process is in place yet for managing secrets and credentials within Ansible and Semaphore.
- **Automated Backups:** The project aims to implement automated backups of the setup, balancing ease of use and security.
- **Fallback/Disaster Recovery:** No fallback or disaster recovery strategy is currently defined.
- **Testing:** No formal process for testing playbooks yet, but test systems are available.
- **Logging and Troubleshooting:** Log files are generated during setup for troubleshooting and auditing.
- **Customization:** Scripts and playbooks will be designed for easy customization to fit different requirements.

## Current Status
- Initial machine setup is nearly fully automated.
- Ansible playbooks are not yet created; the focus will be on neat organization and reusability.
- Playbooks will be shared via a Git repository and executed through Semaphore.
- No additional integrations (e.g., notifications, GitOps) are planned at this stage.

## Intended Audience
This project is intended for system administrators, DevOps engineers, and IT professionals seeking to automate and optimize infrastructure setup and management workflows, as well as for the internal team preparing privacy-focused routers for sale.

## Next Steps / Open Questions
- Develop a process for secure secrets and credential management.
- Design and implement reusable Ansible playbooks for all required services.
- Integrate dynamic inventory with Proxmox.
- Define and implement automated backup and disaster recovery strategies.
- Establish a process for testing playbooks before production use.
- Document best practices for playbook organization and sharing.
