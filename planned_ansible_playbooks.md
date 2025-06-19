# Ansible Playbook Plan

Given the existing setup (Proxmox VM with Ubuntu, Portainer, and Semaphore), the following Ansible playbooks are planned to instantiate and configure the remaining components of the privacy-focused router:

1.  **`provision_opnsense_vm.yml`**
    *   **Purpose:** Create and perform initial OS installation for the OPNSense virtual machine on the Proxmox host.
    *   **Key Tasks:**
        *   Interact with the Proxmox API (using Ansible modules like `community.general.proxmox_kvm`) to define and create the VM (CPU, RAM, disk, network interfaces for WAN/LAN).
        *   Attach the OPNSense installation ISO.
        *   Potentially automate parts of the OPNSense installation process or set it up for a streamlined manual installation.
        *   Ensure basic network connectivity for subsequent Ansible configuration.

2.  **`configure_opnsense_initial.yml`**
    *   **Purpose:** Perform the fundamental configuration of the newly installed OPNSense VM.
    *   **Key Tasks:**
        *   Set the admin password.
        *   Assign and configure network interfaces (WAN, LAN).
        *   Establish basic firewall rules.
        *   Enable SSH access for Ansible.
        *   Configure system settings like hostname, timezone, and initial DNS resolvers.
        *   Update OPNSense to the latest version.

3.  **`deploy_adguard_home_container.yml`**
    *   **Purpose:** Deploy and configure the AdGuard Home container on the existing `ubuntu-server-24.04` VM.
    *   **Key Tasks:**
        *   Use Ansible's Podman modules (e.g., `containers.podman.podman_container`) to pull the AdGuard Home image.
        *   Define and run the AdGuard Home container with necessary volume mounts (for persistent configuration and data) and port mappings.
        *   Configure AdGuard Home:
            *   Set up initial admin user/password.
            *   Define upstream DNS servers (perhaps pointing to Unbound DNS once it's set up).
            *   Import initial blocklists.
            *   Configure client access.

4.  **`deploy_unbound_dns.yml`**
    *   **Purpose:** Deploy and configure Unbound DNS on the `ubuntu-server-24.04` VM (either as a container or a native package).
    *   **Key Tasks:**
        *   Install Unbound (e.g., `apt install unbound` or deploy a container).
        *   Configure Unbound:
            *   Set up listening interfaces.
            *   Define forwarding rules (e.g., to root servers or other privacy-respecting resolvers).
            *   Enable DNSSEC validation.
            *   Configure access control lists.
            *   Set up local zone data or blocklists if needed.
        *   Ensure the Unbound service is running and enabled on boot.

5.  **`manage_opnsense_advanced_features.yml`** (This could be broken into multiple, more specific playbooks or roles)
    *   **Purpose:** Configure advanced features and ongoing settings within OPNSense.
    *   **Key Tasks (Examples):**
        *   VPN server/client setup (e.g., OpenVPN, WireGuard).
        *   Intrusion Detection/Prevention (e.g., Suricata).
        *   Traffic shaping and QoS rules.
        *   DNS over TLS/HTTPS configuration (if using OPNSense for this).
        *   Alias and advanced firewall rule management.
        *   Setting up DHCP server options.

6.  **`common_vm_maintenance.yml`**
    *   **Purpose:** Apply common configurations, updates, and hardening to all managed VMs (OPNSense, Ubuntu server).
    *   **Key Tasks:**
        *   Regular system updates and package management.
        *   User account and SSH key management.
        *   Security hardening (e.g., configuring `fail2ban`, checking for open ports).
        *   NTP client configuration for time synchronization.
        *   Log management and rotation.

7.  **`site.yml` (Main Orchestration Playbook)**
    *   **Purpose:** A top-level playbook to orchestrate the execution of other playbooks/roles in the correct order and manage dependencies.
    *   **Key Tasks:**
        *   Import or include the other playbooks.
        *   Define the overall deployment flow (e.g., provision VM, then configure base, then deploy services).

## Important Considerations for these Playbooks:

*   **Dynamic Inventory:** Set up dynamic inventory in Semaphore, likely using a Proxmox inventory script, so Ansible can automatically discover and target your VMs.
*   **Ansible Roles:** For better organization and reusability, structure these playbooks using Ansible Roles (e.g., an `opnsense` role, `adguard_home` role, `unbound` role).
*   **Secrets Management:** Implement a secure way to handle secrets (API keys, passwords) within Ansible and Semaphore (e.g., Ansible Vault, or integrating Semaphore with an external vault).
*   **Idempotency:** Ensure all tasks and playbooks are idempotent, meaning they can be run multiple times without causing unintended changes.
