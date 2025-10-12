your data is not a product.

***

# PrivateBox

## What is it?

PrivateBox is a collection of shell scripts and Ansible playbooks that automate the deployment of a production-ready network security stack on a Proxmox VE host. It uses a single command to provision a Debian management VM and deploy containerized services, including an OPNsense® firewall, AdGuard Home for DNS filtering, and a Headscale VPN control server. The objective is to provide a repeatable, self-hosted, and fully open-source alternative to commercial firewall appliances.

### Core Components

-   **Automated OPNsense® Deployment**: Deploys and configures an OPNsense® VM to function as the network's primary firewall and router.
-   **Network-Wide DNS Filtering**: Deploys AdGuard Home in a container for DNS-based ad and tracker blocking.
-   **Self-Hosted VPN**: Deploys Headscale (a self-hosted Tailscale control server) for secure remote network access.
-   **One-Command Setup**: A single `quickstart.sh` script orchestrates the entire deployment on a fresh Proxmox host.
-   **Web-Based Management**: Includes Portainer for container management and Semaphore for Ansible automation, both accessible via HTTPS.

---

## System Requirements

-   **Hardware**: A dual-NIC system (e.g., Intel N100 mini-PC) with 8GB+ RAM and 20GB+ available storage.
-   **Software**: Proxmox VE 7.0 or higher.
-   **Network**: A stable internet connection for the initial installation.

## Quick Start

Execute the following command on your Proxmox VE host. This will download and run the bootstrap script.

```bash
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash
```

---
## See it in Action

Watch the 2-minute video to see the entire deployment process, from the `curl` command to the final dashboard.

[![Watch the 2-minute Demo](https://privatebox.com/images/youtube-placeholder.jpg)](https://www.youtube.com/watch?v=dQw4w9WgXcQ)
> *(Link to a 2-minute technical demo video is pending.)*

The script will perform pre-flight checks, configure network bridges, and begin the automated deployment, which takes approximately 15-20 minutes.

---

## Hardware Appliance

We also offer a pre-configured hardware appliance for those who prefer a turnkey solution. The appliance runs the same open-source PrivateBox stack on optimized hardware.

**Specifications:** Intel N100 CPU, 16GB RAM, 256GB NVMe, Dual 2.5GbE NICs.

[**➡️ View Pre-Order & Pricing Information**](https://privatebox.com/preorder)

---

## Deployed Services

The script deploys the following services, which are containerized on the management VM unless otherwise noted.

| Service | Purpose | Access |
| :--- | :--- | :--- |
| **OPNsense®** | Firewall / Router (VM) | `https://opnsense.lan` |
| **AdGuard Home** | DNS Filtering & Ad-Blocking | `https://adguard.lan` |
| **Headscale** | Self-Hosted VPN Server | (CLI / API) |
| **Headplane** | Web UI for Headscale | `https://headplane.lan/admin` |
| **Semaphore** | Ansible Automation UI | `https://semaphore.lan` |
| **Portainer** | Container Management UI | `https://portainer.lan` |
| **Homer** | Service Dashboard | `https://homer.lan` |

**Default Credentials:**
-   **Username**: `admin`
-   **Password**: The `SERVICES_PASSWORD` is auto-generated and output at the end of the installation. It is also stored at `/etc/privatebox/config.env` on the management VM.

<details>
<summary><b>View Deployment Process & Advanced Options</b></summary>

### Deployment Architecture

The `quickstart.sh` script initiates a four-phase deployment:

1.  **Phase 1: Host Preparation**: Installs dependencies, configures Proxmox network bridges (`vmbr0` for WAN, `vmbr1` for LAN), and generates credentials and API tokens for automation.
2.  **Phase 2: VM Provisioning**: Downloads a Debian 13 cloud image and creates the core management VM using `cloud-init` to inject configuration, scripts, and credentials.
3.  **Phase 3: Guest Configuration**: Inside the VM, a script installs and configures the software stack, including Podman, Portainer, and a custom-built Semaphore image that includes Proxmox integration tools.
4.  **Phase 4: Service Orchestration**: The system uses its own Semaphore instance to bootstrap itself, creating the management project, inventories, and environments via its API. It then runs an orchestration script to deploy and configure OPNsense, AdGuard, and all other services in the correct dependency order.

### Installation Arguments

The `quickstart.sh` script accepts several arguments for testing and development.

```bash
# Download the script to review it first (recommended)
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh -o quickstart.sh

# Then run with arguments:
bash quickstart.sh --dry-run      # Run pre-flight checks without creating a VM.
bash quickstart.sh --branch develop # Use a specific git branch for deployment.
bash quickstart.sh --verbose      # Enable detailed script output.
bash quickstart.sh --help         # Display all available arguments.
```

</details>

## Contributing

Contributions are welcome. Please review [CONTRIBUTING.md](CONTRIBUTING.md) for our code of conduct and pull request process.

## License

This project is licensed under the EUPL-1.2. See the [LICENSE](LICENSE) file for details.