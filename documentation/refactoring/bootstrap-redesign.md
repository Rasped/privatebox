# Refined Bootstrap Process

This document outlines the redesigned, robust end-to-end bootstrap process for PrivateBox.

## Guiding Principles

1.  **Single Source of Truth**: A single configuration file, generated at the start, dictates the entire installation.
2.  **Separation of Concerns**: The Proxmox host prepares and provisions the VM. The guest VM configures itself.
3.  **Robust Communication**: Guest-to-host status reporting is handled via a simple, reliable "marker file".
4.  **Atomic Operations**: The installation inside the VM either succeeds completely or fails cleanly with clear logs.

## End-to-End Flow

The process is divided into four distinct phases.

### Phase 1: Host Preparation

*   **Orchestrator**: `bootstrap/bootstrap.sh`
*   **Steps**:
    1.  **Pre-flight Checks**: Verify root access, Proxmox environment, and required host commands.
    2.  **Generate Configuration**: Run `lib/config-generator.sh` to create `config/privatebox.conf`. This file includes discovered network settings and securely generated passwords (`ADMIN_PASSWORD`, `SERVICES_PASSWORD`).
    3.  **Ensure Clean Slate**: Destroy any pre-existing VM with the same VMID.

### Phase 2: VM Provisioning & Payload Delivery

*   **Orchestrator**: `scripts/create-debian-vm.sh`
*   **Steps**:
    1.  **Download Image**: Fetch the Debian cloud image, using a local cache to prevent re-downloads.
    2.  **Prepare Guest Payload**:
        *   **Guest Config File**: Create a simple `guest-config.env` file containing necessary variables (passwords, IP addresses) from `privatebox.conf`.
        *   **Script Bundle**: Package all setup scripts (`initial-setup.sh`, `lib/*`, etc.) into a single `privatebox_setup.tar.gz` tarball.
    3.  **Generate Minimal `cloud-init`**: Create a `user-data.yaml` file with three simple tasks:
        *   `users`: Configure the primary user and inject the host's public SSH key for verification access.
        *   `write_files`: Place `guest-config.env` in `/etc/privatebox/` and the `privatebox_setup.tar.gz` in `/tmp/`.
        *   `runcmd`: A minimal command list to unpack the tarball and execute the main `initial-setup.sh` script.
    4.  **Create & Start VM**: Use `qm` commands to build and launch the configured virtual machine.

### Phase 3: Guest Self-Configuration

*   **Orchestrator**: `initial-setup.sh` (running inside the guest VM)
*   **Steps**:
    1.  **Initialize**: The script starts with `set -euo pipefail` for automatic error handling and sets up logging to `/var/log/privatebox-setup.log`. A `trap` is set to catch any script failure.
    2.  **Load Configuration**: Source the `/etc/privatebox/config.env` file to load all required variables.
    3.  **Execute Modules**: Run the various setup scripts (`portainer-setup.sh`, `semaphore-setup-boltdb.sh`, etc.) in sequence. All sub-scripts inherit the exported configuration.
    4.  **Signal Completion**:
        *   **On Success**: The script's final action is to create a marker file: `echo "SUCCESS" > /etc/privatebox-install-complete`.
        *   **On Failure**: The `trap` catches the error, logs the failure stage, and creates the marker file with failure details: `echo "FAILED: Stage X" > /etc/privatebox-install-complete`.

### Phase 4: Host Verification & Reporting

*   **Orchestrator**: `bootstrap/bootstrap.sh`
*   **Steps**:
    1.  **Wait and Poll**: After starting the VM, the script enters a polling loop (e.g., for 15 minutes).
    2.  **Check Marker File**: Every 20-30 seconds, it uses SSH to read the content of `/etc/privatebox-install-complete` on the guest.
    3.  **Determine Outcome**:
        *   If the file contains "SUCCESS", the installation is marked as successful.
        *   If the file contains "FAILED", it's marked as failed.
        *   If the loop times out, it's marked as a failure.
    4.  **Display Final Status**: The script calls `display_final_status` to show the user the final report, including access credentials on success or debugging instructions on failure.

---

## Detailed Variable and Password Flow

To ensure robustness, we must explicitly track the flow of every piece of information.

### Step 1: The "Source of Truth" (`config/privatebox.conf`)

The `lib/config-generator.sh` script is responsible for creating the master configuration file. It must gather or generate the following variables:

*   **VM Parameters**:
    *   `VMID`: The unique ID for the Proxmox VM.
    *   `VM_MEMORY`: RAM for the VM.
    *   `VM_CORES`: CPU cores for the VM.
    *   `STORAGE`: Proxmox storage location (e.g., `local-lvm`).
*   **Network Configuration**:
    *   `NET_BRIDGE`: The Proxmox bridge to use (e.g., `vmbr0`).
    *   `STATIC_IP`: The IP address for the new VM.
    *   `GATEWAY`: The network gateway.
*   **Credentials (Critical for Production)**:
    *   `VM_USERNAME`: The username for the guest OS (e.g., `debian`).
    *   `ADMIN_PASSWORD`: A securely generated, high-entropy password for the `VM_USERNAME`. This is for direct SSH/console access.
    *   `SERVICES_PASSWORD`: A separate, securely generated password. This will be used specifically for the **admin user of Semaphore**. Reusing the OS password for a web service is bad practice.

### Step 2: The "Guest Payload" (`guest-config.env`)

The `scripts/create-debian-vm.sh` script will create a temporary `guest-config.env` file by selecting a **subset** of variables from `privatebox.conf`. This ensures we don't expose unnecessary host-side details (like `STORAGE` or `NET_BRIDGE`) to the guest.

**Contents of `guest-config.env`**:

```ini
# This file is placed at /etc/privatebox/config.env on the guest
VM_USERNAME="debian"
ADMIN_PASSWORD="<generated-admin-password>"
SERVICES_PASSWORD="<generated-services-password>"
STATIC_IP="<discovered-or-static-ip>"
```

### Step 3: Consumption Inside the Guest

The main `initial-setup.sh` script inside the guest performs the following actions with these variables:

1.  **`source /etc/privatebox/config.env`**: Loads all the above variables into its environment.
2.  **`export VM_USERNAME ADMIN_PASSWORD SERVICES_PASSWORD STATIC_IP`**: Makes these variables available to any sub-script it calls.

### Step 4: Downstream Script Dependencies

Now, the downstream scripts can reliably use these variables:

*   **`cloud-init`**:
    *   Uses `VM_USERNAME` and `ADMIN_PASSWORD` to create the initial user.
*   **`semaphore-setup-boltdb.sh`**:
    *   This is the most critical consumer. It needs the `SERVICES_PASSWORD` to pre-configure the Semaphore admin user, making the UI accessible immediately after installation. It will use this variable directly from its environment.
*   **`portainer-setup.sh`**:
    *   While Portainer setup is often manual on first login, this script could use `SERVICES_PASSWORD` to pre-configure the initial admin password if the Portainer API supports it, further enhancing the hands-off setup.
*   **Display Scripts (`display_final_status`)**:
    *   Back on the **host**, this script reads `privatebox.conf` to show the user the `STATIC_IP`, `VM_USERNAME`, `ADMIN_PASSWORD`, and `SERVICES_PASSWORD` so they know how to log in to the VM and the Semaphore UI.

This explicit flow ensures that every piece of information has a clear origin, a secure transport mechanism, and a well-defined consumer, which is essential for a production-ready, automated system.