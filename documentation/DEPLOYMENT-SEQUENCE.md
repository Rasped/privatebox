# PrivateBox Deployment Sequence

## Purpose of This Document

This document maps the **exact, actual deployment sequence** from a clean Proxmox host to a fully operational PrivateBox system. It is written by tracing through the real code execution path, not documentation or assumptions.

**Why this document exists:**
- Understand what actually happens during deployment (not what should happen)
- Debug deployment issues by identifying which step failed
- Enable new AI contexts to continue work without re-learning the entire codebase
- Serve as the authoritative source for deployment architecture

**How to use this document:**
- Follow steps sequentially - they execute in this order
- Each step lists the actual script/file being executed
- Configuration files, API calls, and state changes are documented
- This is a living document - update it when deployment changes

**Current status:** Being documented (in progress)

---

## Entry Point: quickstart.sh

**Location:** `/path/to/privatebox/quickstart.sh`
**Executed on:** Proxmox host (192.168.1.10 in standard setup)
**Execution:** `curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash`

### Step 1: quickstart.sh Pre-flight Checks

**What happens:**
1. Checks if running as root (exits if not)
2. Verifies Proxmox installation (checks for `/etc/pve` directory)
3. Fixes Proxmox repository configuration:
   - Disables enterprise repositories (comments out `/etc/apt/sources.list.d/pve-enterprise.list`)
   - Disables Ceph enterprise repo (comments out `/etc/apt/sources.list.d/ceph.list`)
   - Enables no-subscription repository (`/etc/apt/sources.list.d/pve-no-subscription.list`)
4. Checks for `git` command - installs if missing:
   - Runs `apt-get update`
   - Runs `apt-get install -y git`
5. Verifies required commands exist: `curl`, `wget`, `qm`
6. Tests internet connectivity: `curl -s --head --connect-timeout 5 https://github.com`

**Files modified:**
- `/etc/apt/sources.list.d/pve-enterprise.list` (commented out)
- `/etc/apt/sources.list.d/ceph.list` (commented out)
- `/etc/apt/sources.list.d/pve-no-subscription.list` (created if missing)

**State after step:** Proxmox repositories configured, git installed, connectivity verified

### Step 2: quickstart.sh Downloads Repository

**What happens:**
1. Removes any existing `/tmp/privatebox-quickstart` directory
2. Clones repository: `git clone --depth 1 --branch main https://github.com/Rasped/privatebox /tmp/privatebox-quickstart`
3. Changes directory to `/tmp/privatebox-quickstart`

**Files created:**
- `/tmp/privatebox-quickstart/` (full repository)

**State after step:** Repository cloned to temp directory

### Step 3: quickstart.sh Invokes bootstrap.sh

**What happens:**
1. Locates `./bootstrap/bootstrap.sh`
2. Passes flags: `--dry-run` (if specified), `--verbose` (if specified)
3. Executes: `bash ./bootstrap/bootstrap.sh [flags]`

**Control transfers to:** `bootstrap/bootstrap.sh`

---

## Bootstrap Phase: bootstrap.sh

**Location:** `/tmp/privatebox-quickstart/bootstrap/bootstrap.sh`
**Executed on:** Proxmox host
**Purpose:** 4-phase orchestrator for VM creation and service deployment

### Step 4: bootstrap.sh Initialization

**What happens:**
1. Sets script directory: `SCRIPT_DIR=/tmp/privatebox-quickstart/bootstrap`
2. Sets library directory: `LIB_DIR=/tmp/privatebox-quickstart/bootstrap/lib`
3. Creates log file: `/tmp/privatebox-bootstrap.log`
4. Sets config file: `/tmp/privatebox-config.conf`
5. Parses arguments: `--dry-run`, `--verbose`
6. Sets default VM ID: `VMID=9000`

**Files created:**
- `/tmp/privatebox-bootstrap.log` (log file initialized)

**State after step:** Logging initialized, variables set

### Step 5: bootstrap.sh Phase 1 - Host Preparation

**What happens:**
1. Executes: `${SCRIPT_DIR}/prepare-host.sh`

**Control transfers to:** `bootstrap/prepare-host.sh`

---

## Phase 1: Host Preparation (prepare-host.sh)

**Location:** `/tmp/privatebox-quickstart/bootstrap/prepare-host.sh`
**Executed on:** Proxmox host
**Purpose:** Install dependencies, configure network, generate credentials

### Step 6: Pre-flight Checks and Dependencies

**What happens:**
1. Verifies running as root (exits if not)
2. Verifies Proxmox environment (checks `/etc/pve` exists)
3. Verifies `qm` command exists
4. Checks for required commands and installs if missing:
   - `ethtool`, `sshpass`, `zstd`, `curl`, `wget`, `openssl`
   - Runs `apt-get update` if packages need installing
   - Runs `DEBIAN_FRONTEND=noninteractive apt-get install -y [packages]`
5. Checks if VM 9000 exists:
   - If exists and running: stops it with 30s timeout
   - If exists: destroys it with `qm destroy 9000 --purge`
6. Checks available disk space on `local-lvm` storage:
   - Requires minimum 15GB
   - Uses `pvesm status -storage local-lvm`

**Files modified:**
- `/var/lib/apt/lists/*` (apt update)
- `/usr/bin/ethtool`, `/usr/bin/sshpass`, `/usr/bin/zstd` (if installed)

**State after step:** Dependencies installed, existing VM 9000 removed, disk space verified

### Step 7: SSH Key Generation

**What happens:**
1. Checks if `/root/.ssh/id_rsa` exists
2. If not exists:
   - Creates `/root/.ssh/` directory (mode 700)
   - Generates 4096-bit RSA key: `ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "privatebox@$(hostname)"`
   - Sets permissions: 600 on private key, 644 on public key

**Files created:**
- `/root/.ssh/id_rsa` (private key, mode 600)
- `/root/.ssh/id_rsa.pub` (public key, mode 644)

**State after step:** SSH keypair available at `/root/.ssh/id_rsa`

### Step 8: Network Detection and Bridge Configuration

**What happens:**
1. **WAN Bridge Detection:**
   - Finds default route: `ip route | grep "^default"`
   - Extracts bridge name (typically `vmbr0`)
   - Gets Proxmox IP on that bridge
   - Sets `WAN_BRIDGE` and `PROXMOX_IP` variables

2. **vmbr1 Bridge Setup (Internal Network):**
   - Checks if `vmbr1` exists with `ip link show vmbr1`
   - If exists with physical NIC and VLAN support: skip
   - If exists without physical NIC or VLAN support: fix configuration
   - If doesn't exist: create it

3. **Finding Second NIC for vmbr1:**
   - Lists all NICs matching `enp*`, `eno*`, or `eth*`
   - Finds first NIC not assigned to any bridge
   - Checks link status with `ethtool`
   - If no unassigned NIC found: exits with error (dual NIC required)

4. **Creating/Fixing vmbr1:**
   - Adds configuration to `/etc/network/interfaces`:
     ```
     auto vmbr1
     iface vmbr1 inet manual
         bridge-ports [NIC]
         bridge-stp off
         bridge-fd 0
         bridge-vlan-aware yes
         bridge-vids 2-4094
     ```
   - Brings up bridge with `ifup vmbr1`

5. **Services VLAN Configuration (VLAN 20):**
   - Checks if `vmbr1.20` exists with IP `10.10.20.20/24`
   - If not configured, adds to `/etc/network/interfaces`:
     ```
     auto vmbr1.20
     iface vmbr1.20 inet static
         address 10.10.20.20/24
     ```
   - Brings up VLAN with `ifup vmbr1.20` or manual commands:
     ```
     ip link add link vmbr1 name vmbr1.20 type vlan id 20
     ip link set vmbr1.20 up
     ip addr add 10.10.20.20/24 dev vmbr1.20
     ```
   - Removes conflicting IP from untagged vmbr1 if present
   - Tests connectivity to OPNsense at `10.10.20.1` (won't succeed yet)

**Files modified:**
- `/etc/network/interfaces` (bridge and VLAN configuration appended)

**State after step:**
- `vmbr0` = WAN bridge (existing)
- `vmbr1` = LAN bridge on second NIC, VLAN-aware
- `vmbr1.20` = Services VLAN with IP 10.10.20.20/24
- Proxmox can communicate on Services VLAN

### Step 9: HTTPS Certificate Generation

**What happens:**
1. Creates directory: `/etc/privatebox/certs/`
2. Generates self-signed certificate (10 year validity):
   ```
   openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
     -subj "/C=DK/O=PrivateBox/CN=privatebox.local" \
     -keyout /etc/privatebox/certs/privatebox.key \
     -out /etc/privatebox/certs/privatebox.crt
   ```
3. Sets permissions: 644 on both files

**Files created:**
- `/etc/privatebox/certs/privatebox.crt` (certificate, mode 644)
- `/etc/privatebox/certs/privatebox.key` (private key, mode 644)

**State after step:** Self-signed certificate ready for services

### Step 10: Configuration Generation and Proxmox API Token

**What happens:**
1. **Password Generation:**
   - Sources `bootstrap/lib/password-generator.sh`
   - Generates 2 phonetic passwords:
     - `admin_password` = 5 words (e.g., "hypnoTiz3-4FaR-hand1er-uNcoi1Ed-5pliNTEr")
     - `services_password` = 3 words (e.g., "emP0wer-curs3-sacram3Nt")

2. **Proxmox API Token Creation:**
   - Creates user: `pveum user add automation@pve`
   - Removes existing token if present: `pveum user token remove automation@pve ansible`
   - Creates new token: `pveum user token add automation@pve ansible --privsep 0 --output-format json`
   - Extracts token secret from JSON output
   - Sets permissions:
     - `/vms` → `PVEVMAdmin` role
     - `/storage` → `PVEDatastoreUser` role
     - `/nodes` → `PVEAuditor` role
   - Token ID: `automation@pve!ansible`

3. **Writes Configuration File** (`/tmp/privatebox-config.conf`):
   ```bash
   # WAN Network
   WAN_BRIDGE="vmbr0"
   PROXMOX_IP="192.168.1.10"

   # Services VLAN (10.10.20.0/24)
   SERVICES_NETWORK="10.10.20"
   SERVICES_GATEWAY="10.10.20.1"
   SERVICES_NETMASK="24"
   MGMT_VM_IP="10.10.20.10"
   PROXMOX_SERVICES_IP="10.10.20.20"

   # VM Configuration
   VMID="9000"
   VM_USERNAME="debian"
   VM_MEMORY="2048"
   VM_CORES="2"
   VM_DISK_SIZE="15G"
   VM_STORAGE="local-lvm"

   # Credentials
   ADMIN_PASSWORD="[generated]"
   SERVICES_PASSWORD="[generated]"

   # Proxmox API Token
   PROXMOX_TOKEN_ID="automation@pve!ansible"
   PROXMOX_TOKEN_SECRET="[generated]"
   PROXMOX_API_HOST="192.168.1.10"
   PROXMOX_NODE="[hostname]"

   # Legacy compatibility
   STATIC_IP="10.10.20.10"
   GATEWAY="10.10.20.1"
   NETMASK="24"
   CONTAINER_HOST_IP="10.10.20.10"
   PROXMOX_HOST="192.168.1.10"
   ```

**Files created:**
- `/tmp/privatebox-config.conf` (all configuration variables)

**Proxmox changes:**
- User `automation@pve` created
- Token `automation@pve!ansible` created with permissions

**State after step:** Complete configuration generated, Proxmox API ready for automation

**Control returns to:** `bootstrap/bootstrap.sh`

---

## Phase 2: OPNsense Deployment (deploy-opnsense.sh)

**Location:** `/tmp/privatebox-quickstart/bootstrap/deploy-opnsense.sh`
**Executed on:** Proxmox host
**Purpose:** Deploy OPNsense firewall VM as network gateway

### Step 11: OPNsense Script Check

**What happens:**
1. `bootstrap.sh` checks if `deploy-opnsense.sh` exists
2. If missing: displays warning and skips (allows testing without firewall)
3. If exists: executes the script
4. On failure: exits with error (firewall is required for production)

**Expected outcome:** OPNsense deployment attempted (script execution documented separately when implemented)

**Control returns to:** `bootstrap/bootstrap.sh` (Phase 3)

---

## Phase 3: Management VM Provisioning (create-vm.sh)

**Location:** `/tmp/privatebox-quickstart/bootstrap/create-vm.sh`
**Executed on:** Proxmox host
**Purpose:** Create Debian 13 management VM with cloud-init setup

### Step 12: Download Debian Cloud Image

**What happens:**
1. Sets image URL: `https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2`
2. Sets cache path: `/var/lib/vz/template/cache/debian-13-genericcloud-amd64.qcow2`
3. Creates cache directory: `mkdir -p /var/lib/vz/template/cache`
4. Checks if image already cached at path
5. If cached: uses existing file
6. If not cached:
   - Downloads with `wget -q --show-progress -O [path] [URL]`
   - On failure: removes partial file and exits
7. Verifies image:
   - File exists
   - File size > 1MB (validates not corrupted)
   - On failure: removes file and exits
8. Sets variable: `DEBIAN_IMAGE=/var/lib/vz/template/cache/debian-13-genericcloud-amd64.qcow2`

**Files created:**
- `/var/lib/vz/template/cache/debian-13-genericcloud-amd64.qcow2` (Debian cloud image, ~200-400MB)

**State after step:** Debian cloud image available locally

### Step 13: Create Setup Package

**What happens:**
1. Removes existing work directory: `rm -rf /tmp/privatebox-vm-creation`
2. Creates work structure: `mkdir -p /tmp/privatebox-vm-creation/privatebox-setup`
3. Generates guest config file: `/tmp/privatebox-vm-creation/privatebox-setup/config.env`
   - Contains subset of main config for use inside VM:
     - `VM_USERNAME` (typically "debian")
     - `ADMIN_PASSWORD` (5-word phonetic password)
     - `SERVICES_PASSWORD` (3-word phonetic password)
     - `STATIC_IP` (10.10.20.10)
     - `GATEWAY` (10.10.20.1)
     - `NETMASK` (24)
     - `PROXMOX_TOKEN_ID` (automation@pve!ansible)
     - `PROXMOX_TOKEN_SECRET` (API secret)
     - `PROXMOX_API_HOST` (192.168.1.10)
     - `PROXMOX_NODE` (hostname)
4. Loads `setup-guest.sh` content into variable for cloud-init embedding
   - Indents lines with 6 spaces (for YAML embedding)
   - Verifies file exists, exits on failure

**Files created:**
- `/tmp/privatebox-vm-creation/privatebox-setup/config.env` (guest configuration)

**State after step:** Setup package prepared for cloud-init injection

### Step 14: Generate Cloud-Init Configuration

**What happens:**
1. **Enable Snippets Storage:**
   - Checks if `local` storage supports snippets
   - If not: runs `pvesm set local --content vztmpl,iso,backup,snippets`
   - Creates directory: `mkdir -p /var/lib/vz/snippets`

2. **Load SSH Keys:**
   - Reads Proxmox public key: `/root/.ssh/id_rsa.pub` (for VM access)
   - Reads Proxmox private key: `/root/.ssh/id_rsa` (for Semaphore to access Proxmox)
   - Indents private key with 6 spaces for YAML embedding

3. **Load Semaphore API Library:**
   - Reads `bootstrap/lib/semaphore-api.sh`
   - Indents content with 6 spaces for YAML embedding

4. **Create Cloud-Init User-Data Snippet** (`/var/lib/vz/snippets/privatebox-9000.yml`):
   ```yaml
   #cloud-config
   hostname: privatebox-management
   manage_etc_hosts: true

   users:
     - name: debian
       sudo: ALL=(ALL) NOPASSWD:ALL
       shell: /bin/bash
       lock_passwd: false
       passwd: [hashed admin password using openssl passwd -6]
       ssh_authorized_keys:
         - [proxmox public key]

   ssh_pwauth: true

   write_files:
     - path: /etc/privatebox/config.env
       permissions: '0600'
       content: [guest config from step 13]

     - path: /usr/local/bin/setup-guest.sh
       permissions: '0755'
       content: [setup-guest.sh script content]

     - path: /root/.credentials/proxmox_ssh_key
       permissions: '0600'
       owner: root:root
       content: [proxmox private SSH key]

     - path: /etc/privatebox-proxmox-host
       permissions: '0644'
       owner: root:root
       content: [PROXMOX_HOST IP]

     - path: /usr/local/lib/semaphore-api.sh
       permissions: '0755'
       owner: root:root
       content: [semaphore API library]

     - path: /etc/privatebox/certs/privatebox.crt
       permissions: '0644'
       owner: root:root
       content: [self-signed certificate from step 9]

     - path: /etc/privatebox/certs/privatebox.key
       permissions: '0644'
       owner: root:root
       content: [certificate private key from step 9]

   runcmd:
     - [mkdir, -p, /etc/privatebox]
     - [mkdir, -p, /etc/privatebox/certs]
     - [mkdir, -p, /var/log]
     - ['/bin/bash', '/usr/local/bin/setup-guest.sh']

   final_message: "PrivateBox bootstrap phase 3 initiated"
   ```

**Files created:**
- `/var/lib/vz/snippets/privatebox-9000.yml` (cloud-init user-data)

**State after step:** Cloud-init snippet ready with all credentials and scripts embedded

### Step 15: Create and Configure VM

**What happens:**
1. **Create VM** (ID 9000):
   ```bash
   qm create 9000 \
     --name privatebox-management \
     --memory 2048 \
     --cores 2 \
     --cpu host \
     --net0 virtio,bridge=vmbr1,tag=20 \
     --serial0 socket \
     --vga serial0 \
     --agent enabled=1
   ```
   - Network attached to vmbr1 with VLAN tag 20 (Services VLAN)
   - Serial console enabled for troubleshooting
   - QEMU guest agent enabled

2. **Import Disk Image:**
   ```bash
   qm importdisk 9000 /var/lib/vz/template/cache/debian-13-genericcloud-amd64.qcow2 local-lvm
   ```
   - Imports Debian cloud image to `local-lvm` storage
   - Creates disk: `vm-9000-disk-0`

3. **Attach and Configure Disk:**
   ```bash
   qm set 9000 \
     --scsihw virtio-scsi-pci \
     --scsi0 local-lvm:vm-9000-disk-0 \
     --boot c --bootdisk scsi0
   ```
   - Uses VirtIO SCSI controller (better performance)
   - Sets disk as bootable

4. **Resize Disk:**
   ```bash
   qm resize 9000 scsi0 15G
   ```
   - Expands disk to 15GB (from ~2GB base image)

5. **Add Cloud-Init Drive:**
   ```bash
   qm set 9000 --ide2 local-lvm:cloudinit
   ```
   - Creates special cloud-init configuration drive

6. **Enable Auto-Start:**
   ```bash
   qm set 9000 --onboot 1
   ```
   - VM starts automatically with Proxmox

7. **Configure Cloud-Init Network and Custom Snippet:**
   ```bash
   qm set 9000 \
     --ipconfig0 ip=10.10.20.10/24,gw=10.10.20.1 \
     --nameserver 10.10.20.1 \
     --cicustom "user=local:snippets/privatebox-9000.yml"
   ```
   - Static IP configuration: 10.10.20.10/24
   - Gateway: 10.10.20.1 (OPNsense)
   - DNS: 10.10.20.1 (will be AdGuard via OPNsense)
   - Links custom user-data snippet from step 14

**Proxmox storage changes:**
- `local-lvm:vm-9000-disk-0` (15GB SCSI disk)
- `local-lvm:vm-9000-cloudinit` (cloud-init config drive)

**VM Configuration created:**
- VM ID: 9000
- Name: privatebox-management
- Resources: 2 cores, 2GB RAM, 15GB disk
- Network: vmbr1 VLAN 20 (10.10.20.10/24)
- Boot: Auto-start enabled

**State after step:** VM fully configured, ready to start

### Step 16: Start VM

**What happens:**
1. Starts VM: `qm start 9000`
2. Polls VM status every second for up to 30 seconds
3. Checks if status shows "running": `qm status 9000 | grep "running"`
4. On success: logs confirmation and returns
5. On timeout: exits with error

**State after step:** VM 9000 running, cloud-init begins execution

**What cloud-init does (automated, inside VM):**
1. Applies hostname and network configuration
2. Creates `debian` user with sudo and password
3. Writes all files from `write_files` section:
   - `/etc/privatebox/config.env`
   - `/usr/local/bin/setup-guest.sh`
   - `/root/.credentials/proxmox_ssh_key`
   - `/etc/privatebox-proxmox-host`
   - `/usr/local/lib/semaphore-api.sh`
   - `/etc/privatebox/certs/privatebox.{crt,key}`
4. Creates directories: `/etc/privatebox`, `/etc/privatebox/certs`, `/var/log`
5. Executes: `/bin/bash /usr/local/bin/setup-guest.sh`
   - This is **Phase 4** (documented separately)

**Control returns to:** `bootstrap/bootstrap.sh` (Phase 4 monitoring)

---

## Phase 4: Guest Configuration (setup-guest.sh)

**Location:** `/usr/local/bin/setup-guest.sh` (embedded in cloud-init from `bootstrap/setup-guest.sh`)
**Executed on:** Management VM (inside guest)
**Triggered by:** cloud-init `runcmd` section
**Purpose:** Install Podman, configure Portainer/Semaphore, deploy services via Semaphore API

### Step 17: Guest Bootstrap and Logging

**What happens:**
1. Sources configuration: `/etc/privatebox/config.env`
2. Verifies `SERVICES_PASSWORD` is set (exits on failure)
3. Sets up logging to `/var/log/privatebox-guest-setup.log`
4. Redirects all output to log file with `tee`
5. Creates marker file: `/etc/privatebox-install-complete`
6. Writes progress: `PROGRESS:Starting guest configuration`

**Files created:**
- `/var/log/privatebox-guest-setup.log` (setup log)
- `/etc/privatebox-install-complete` (progress marker for bootstrap monitoring)

**State after step:** Logging initialized, configuration loaded

### Step 18: System Package Installation

**What happens:**
1. **Updates package lists:**
   ```bash
   apt-get update
   ```
   - Progress marker: `PROGRESS:Updating system packages`

2. **Upgrades all packages:**
   ```bash
   DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
   ```

3. **Installs required packages:**
   ```bash
   DEBIAN_FRONTEND=noninteractive apt-get install -y \
     curl wget ca-certificates gnupg lsb-release jq git \
     podman buildah skopeo openssh-client
   ```
   - `podman` - Container runtime (Docker alternative)
   - `buildah` - Container image building
   - `skopeo` - Container image management
   - `jq` - JSON parsing for API calls
   - `git` - Repository operations
   - `openssh-client` - SSH operations

**Files modified:**
- System packages updated and installed

**State after step:** All dependencies installed, system fully updated

### Step 19: Podman Socket Configuration

**What happens:**
1. **Enable Podman socket:**
   ```bash
   systemctl enable --now podman.socket
   ```
   - Provides Docker-compatible API at `/run/podman/podman.sock`
   - Required for Portainer to manage containers

2. **Auto-update disabled:**
   - Automatic container updates not enabled
   - Updates will be manual via Semaphore

**Files created:**
- `/run/podman/podman.sock` (Docker-compatible API socket)

**Systemd units enabled:**
- `podman.socket` (active and enabled)

**State after step:** Podman socket running, Docker API available

### Step 20: Directory and Volume Creation

**What happens:**
1. **Create persistent directories:**
   ```bash
   mkdir -p /opt/portainer/data
   mkdir -p /opt/semaphore/{data,config,projects,ansible}
   mkdir -p /etc/containers/systemd
   mkdir -p /usr/local/lib
   mkdir -p /root/.credentials
   ```

2. **Set permissions for Semaphore:**
   ```bash
   chown -R 1001:1001 /opt/semaphore
   ```
   - Semaphore container runs as uid 1001 (non-root)

3. **Create Podman volume for Portainer:**
   ```bash
   podman volume create snippets
   ```
   - Used for Portainer Stack file storage

**Directories created:**
- `/opt/portainer/data` - Portainer configuration and data
- `/opt/semaphore/data` - Semaphore database (BoltDB)
- `/opt/semaphore/config` - Semaphore config.json
- `/opt/semaphore/projects` - Cloned repositories and playbooks
- `/opt/semaphore/ansible` - Ansible home directory cache
- `/etc/containers/systemd` - Podman Quadlet unit files
- `/root/.credentials` - Temporary credential storage

**Podman volumes:**
- `snippets` (Portainer stack storage)

**State after step:** Directory structure ready for services

### Step 21: Build Custom Semaphore Image

**What happens:**
1. **Write Containerfile** (`/opt/semaphore/Containerfile`):
   ```dockerfile
   FROM docker.io/semaphoreui/semaphore:latest
   USER root
   RUN pip3 install --no-cache-dir proxmoxer requests
   USER semaphore
   ```
   - Adds Python libraries for Proxmox API (`proxmoxer`, `requests`)
   - Required for Ansible Proxmox modules

2. **Build custom image:**
   ```bash
   podman build -t localhost/semaphore-proxmox:latest /opt/semaphore
   ```
   - Progress marker: `PROGRESS:Building custom Semaphore image`
   - Image tagged as `localhost/semaphore-proxmox:latest`
   - Built locally (not pulled from registry)

**Files created:**
- `/opt/semaphore/Containerfile` (build instructions)

**Container images:**
- `localhost/semaphore-proxmox:latest` (custom Semaphore with Proxmox support)

**State after step:** Custom Semaphore image ready for deployment

### Step 22: Create Portainer Quadlet

**What happens:**
1. **Write Quadlet unit** (`/etc/containers/systemd/portainer.container`):
   ```ini
   [Unit]
   Description=Portainer Container
   Wants=network-online.target podman.socket
   After=network-online.target podman.socket

   [Container]
   Image=docker.io/portainer/portainer-ce:latest
   ContainerName=portainer
   Volume=/run/podman/podman.sock:/var/run/docker.sock:z
   Volume=/opt/portainer/data:/data:z
   Volume=snippets:/snippets:z
   Volume=/etc/privatebox/certs:/certs:ro,z
   PublishPort=1443:9443
   Environment=TZ=UTC
   Exec=--ssl --sslcert /certs/privatebox.crt --sslkey /certs/privatebox.key

   [Service]
   Restart=always
   TimeoutStartSec=300

   [Install]
   WantedBy=multi-user.target default.target
   ```
   - Systemd Quadlet format (auto-converts to systemd unit)
   - Binds to port 1443 on host (maps to 9443 in container)
   - HTTPS enabled with self-signed cert from step 9
   - Podman socket mounted for container management

**Files created:**
- `/etc/containers/systemd/portainer.container` (Quadlet unit)

**State after step:** Portainer configured, awaiting systemd reload

### Step 23: Generate Semaphore Configuration

**What happens:**
1. **Generate random secrets:**
   ```bash
   COOKIE_HASH=$(head -c32 /dev/urandom | base64 | head -c44)
   COOKIE_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)
   ACCESS_KEY_ENCRYPTION=$(head -c32 /dev/urandom | base64 | head -c32)
   ```

2. **Write config.json** (`/opt/semaphore/config/config.json`):
   ```json
   {
     "bolt": { "host": "/var/lib/semaphore/database.boltdb" },
     "dialect": "bolt",
     "port": ":3000",
     "tmp_path": "/tmp/semaphore",
     "cookie_hash": "[random]",
     "cookie_encryption": "[random]",
     "access_key_encryption": "[random]",
     "tls": {
       "enabled": true,
       "cert_file": "/certs/privatebox.crt",
       "key_file": "/certs/privatebox.key"
     },
     "email": { "alert": false },
     "telegram": { "alert": false },
     "ldap": { "enable": false },
     "password_login_disable": false,
     "non_admin_can_create_project": false
   }
   ```
   - BoltDB (embedded database, no external DB needed)
   - HTTPS enabled on port 3000
   - Alerts disabled (email, Telegram)
   - Only admins can create projects

**Files created:**
- `/opt/semaphore/config/config.json` (Semaphore configuration)

**State after step:** Semaphore configured with secure random secrets

### Step 24: Create Semaphore Quadlet

**What happens:**
1. **Write Quadlet unit** (`/etc/containers/systemd/semaphore.container`):
   ```ini
   [Unit]
   Description=Semaphore Container
   Wants=network-online.target
   After=network-online.target

   [Container]
   Image=localhost/semaphore-proxmox:latest
   ContainerName=semaphore
   Volume=/opt/semaphore/data:/var/lib/semaphore:Z
   Volume=/opt/semaphore/config:/etc/semaphore:Z
   Volume=/opt/semaphore/projects:/projects:Z
   Volume=/opt/semaphore/ansible:/home/semaphore/.ansible:Z
   Volume=/etc/privatebox/certs:/certs:ro,z
   PublishPort=2443:3000
   Environment=SEMAPHORE_DB_DIALECT=bolt
   Environment=SEMAPHORE_DB_PATH=/var/lib/semaphore/database.boltdb
   Environment=SEMAPHORE_ADMIN=admin
   Environment=SEMAPHORE_ADMIN_PASSWORD=[from SERVICES_PASSWORD]
   Environment=SEMAPHORE_ADMIN_NAME=Administrator
   Environment=SEMAPHORE_ADMIN_EMAIL=admin@privatebox.local
   Environment=SEMAPHORE_CONFIG_PATH=/etc/semaphore/config.json
   Environment=SEMAPHORE_PLAYBOOK_PATH=/projects
   Exec=semaphore server --config=/etc/semaphore/config.json

   [Service]
   Restart=always
   TimeoutStartSec=300

   [Install]
   WantedBy=multi-user.target default.target
   ```
   - Uses custom image built in step 21
   - Binds to port 2443 on host (maps to 3000 in container)
   - Admin user auto-created via environment variables

**Files created:**
- `/etc/containers/systemd/semaphore.container` (Quadlet unit)

**State after step:** Semaphore configured, awaiting systemd reload

### Step 25: Configure Nightly Image Rebuild

**What happens:**
1. **Write rebuild service** (`/etc/systemd/system/semaphore-image-update.service`):
   ```ini
   [Unit]
   Description=Rebuild custom Semaphore image (with proxmoxer)

   [Service]
   Type=oneshot
   WorkingDirectory=/opt/semaphore
   ExecStart=/usr/bin/podman build -t localhost/semaphore-proxmox:latest .
   ```

2. **Write rebuild timer** (`/etc/systemd/system/semaphore-image-update.timer`):
   ```ini
   [Unit]
   Description=Nightly rebuild for custom Semaphore image

   [Timer]
   OnCalendar=daily
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```
   - Runs daily to rebuild Semaphore image with latest base
   - Ensures security updates from upstream

**Files created:**
- `/etc/systemd/system/semaphore-image-update.service` (rebuild service)
- `/etc/systemd/system/semaphore-image-update.timer` (daily timer)

**State after step:** Auto-update configured for Semaphore image

### Step 26: Start Services via Systemd

**What happens:**
1. **Reload systemd daemon:**
   ```bash
   systemctl daemon-reload
   ```
   - Processes Quadlet files from `/etc/containers/systemd/`
   - Generates systemd service units automatically

2. **Enable nightly rebuild timer:**
   ```bash
   systemctl enable --now semaphore-image-update.timer
   ```

3. **Start Portainer:**
   ```bash
   systemctl start portainer.service
   ```
   - Progress marker: `PROGRESS:Starting Portainer service`
   - Service auto-generated from Quadlet file

4. **Wait for Portainer readiness:**
   - Polls `https://localhost:1443/api/status` every 5 seconds
   - Timeout: 30 attempts (2.5 minutes)

5. **Start Semaphore:**
   ```bash
   systemctl start semaphore.service
   ```
   - Progress marker: `PROGRESS:Starting Semaphore service`

6. **Wait for Semaphore readiness:**
   - Polls `https://localhost:2443/api/ping` every 2 seconds
   - Timeout: 60 attempts (2 minutes)

**Systemd units started:**
- `portainer.service` (running)
- `semaphore.service` (running)
- `semaphore-image-update.timer` (enabled)

**State after step:** Portainer and Semaphore running, APIs accessible

### Step 27: Create Semaphore Admin User

**What happens:**
1. **Get Semaphore container image name:**
   ```bash
   IMAGE=$(podman container inspect -f '{{.ImageName}}' semaphore)
   ```
   - Typically `localhost/semaphore-proxmox:latest`

2. **Stop Semaphore service:**
   ```bash
   systemctl stop semaphore.service
   sleep 2
   ```
   - Required because admin user creation modifies database directly

3. **Create admin user:**
   ```bash
   podman run --rm \
     -v /opt/semaphore/config:/etc/semaphore:Z \
     -v /opt/semaphore/data:/var/lib/semaphore:Z \
     localhost/semaphore-proxmox:latest semaphore user add \
     --admin \
     --login admin \
     --name "Administrator" \
     --email admin@privatebox.local \
     --password "${SERVICES_PASSWORD}" \
     --config /etc/semaphore/config.json
   ```
   - Progress marker: `PROGRESS:Creating Semaphore admin user`
   - Runs one-shot container to add user to database
   - Idempotent (ignores "already exists" errors)

4. **Restart Semaphore:**
   ```bash
   systemctl start semaphore.service
   ```

5. **Wait for API readiness again:**
   - Polls `https://localhost:2443/api/ping` every 2 seconds
   - Timeout: 30 attempts (1 minute)

**BoltDB changes:**
- Admin user `admin` created in `/opt/semaphore/data/database.boltdb`

**State after step:** Semaphore running with admin user ready for API access

---

## Phase 4 (continued): Semaphore API Bootstrap

**Purpose:** Configure Semaphore via API to manage PrivateBox infrastructure

### Step 28: Load Semaphore API Library and Generate VM SSH Key

**What happens:**
1. **Load API library:**
   - Sources `/usr/local/lib/semaphore-api.sh`
   - This file was embedded in cloud-init (step 14)
   - Contains all Semaphore API interaction functions

2. **Check for existing VM SSH key:**
   - Checks if `/root/.credentials/semaphore_vm_key` already exists
   - If missing, generates new key pair

3. **Generate VM SSH key pair:**
   - Function: `generate_vm_ssh_key_pair()` (semaphore-api.sh:1230)
   - Creates directory: `/root/.credentials/` (mode 700)
   - Removes any existing keys at path
   - Generates Ed25519 key pair:
     ```bash
     ssh-keygen -t ed25519 -f /root/.credentials/semaphore_vm_key \
       -C "semaphore-vm-self-management@privatebox-management" -N "" -q
     ```
   - Key is for VM to SSH to itself (Ansible tasks running in Semaphore container)

4. **Add public key to authorized_keys:**
   - Appends public key to `/root/.ssh/authorized_keys`
   - Allows Semaphore container to SSH to VM host as root
   - Sets permissions: 600 on authorized_keys

**Files created:**
- `/root/.credentials/semaphore_vm_key` (Ed25519 private key, mode 600)
- `/root/.credentials/semaphore_vm_key.pub` (public key, mode 644)

**Files modified:**
- `/root/.ssh/authorized_keys` (VM public key appended)

**State after step:** VM can SSH to itself using Ed25519 key

### Step 29: Initialize Semaphore API Session

**What happens:**
1. **Call main entry point:**
   - Function: `create_default_projects()` (semaphore-api.sh:1207)
   - This orchestrates all Semaphore API configuration

2. **Wait for Semaphore API:**
   - Function: `wait_for_semaphore_api()` (semaphore-api.sh:557)
   - Polls: `https://localhost:2443/api/ping`
   - Interval: 10 seconds
   - Timeout: 30 attempts (5 minutes)
   - Extra sleep: 5 seconds after first successful ping

3. **Obtain admin session cookie:**
   - Function: `get_admin_session()` (semaphore-api.sh:577)
   - API endpoint: `POST https://localhost:2443/api/auth/login`
   - Payload:
     ```json
     {
       "auth": "admin",
       "password": "<SERVICES_PASSWORD from config.env>"
     }
     ```
   - Response: Session cookie in `Set-Cookie` header
   - Extracts cookie value: `semaphore=<session-token>`
   - Retry logic: 5 attempts with 15-second delay
   - Used for all subsequent API calls

**API calls:**
- `GET https://localhost:2443/api/ping` (health check, retry loop)
- `POST https://localhost:2443/api/auth/login` (authentication)

**State after step:** Admin session cookie obtained, ready for API operations

### Step 30: Create PrivateBox Project

**What happens:**
1. **Execute project creation:**
   - Function: `create_infrastructure_project_with_ssh_key()` (semaphore-api.sh:1067)
   - Progress marker: `PROGRESS:Creating PrivateBox project` → `/etc/privatebox-install-complete`

2. **Prepare project payload:**
   - Project name: "PrivateBox"
   - Description: "PrivateBox infrastructure management"
   - Git URL: `https://github.com/Rasped/privatebox` (from `PRIVATEBOX_GIT_URL`)
   - Git branch: "main"

3. **Create project via API:**
   - API endpoint: `POST https://localhost:2443/api/projects`
   - Headers:
     ```
     Cookie: semaphore=<session-cookie>
     Content-Type: application/json
     ```
   - Payload:
     ```json
     {
       "name": "PrivateBox",
       "description": "PrivateBox infrastructure management",
       "git_url": "https://github.com/Rasped/privatebox",
       "git_branch": "main"
     }
     ```
   - Response (success):
     ```json
     {
       "id": 1,
       "name": "PrivateBox",
       "created": "2025-01-06T...",
       ...
     }
     ```
   - Extracts project ID from response (typically `1`)

**API calls:**
- `POST https://localhost:2443/api/projects`

**BoltDB changes:**
- Project record created in `/opt/semaphore/data/database.boltdb`

**State after step:** PrivateBox project exists with ID 1

### Step 31: Upload SSH Keys to Semaphore

**What happens:**
1. **Progress marker:**
   - Writes: `PROGRESS:Uploading SSH keys` → `/etc/privatebox-install-complete`

2. **Upload Proxmox SSH key:**
   - Reads private key: `/root/.credentials/proxmox_ssh_key`
   - This key was embedded in cloud-init (step 14)
   - API endpoint: `POST https://localhost:2443/api/project/1/keys`
   - Payload:
     ```json
     {
       "name": "proxmox",
       "type": "ssh",
       "project_id": 1,
       "ssh": {
         "private_key": "<Proxmox SSH private key content>"
       }
     }
     ```
   - Response extracts key ID (typically `1`)
   - **Deletes key file after upload:** `rm -f /root/.credentials/proxmox_ssh_key`
   - Security: Private key removed from filesystem after storing in Semaphore

3. **Upload VM self-management SSH key:**
   - Reads private key: `/root/.credentials/semaphore_vm_key` (from step 28)
   - API endpoint: `POST https://localhost:2443/api/project/1/keys`
   - Payload:
     ```json
     {
       "name": "container-host",
       "type": "ssh",
       "project_id": 1,
       "ssh": {
         "private_key": "<VM Ed25519 private key content>"
       }
     }
     ```
   - Response extracts key ID (typically `2`)
   - **Note:** This file is NOT deleted (may be needed for debugging)

**API calls:**
- `POST https://localhost:2443/api/project/1/keys` (Proxmox key)
- `POST https://localhost:2443/api/project/1/keys` (VM key)

**Files deleted:**
- `/root/.credentials/proxmox_ssh_key` (security cleanup)

**BoltDB changes:**
- SSH key records created in project 1

**State after step:**
- Proxmox SSH key (ID 1) stored in Semaphore
- VM SSH key (ID 2) stored in Semaphore
- Proxmox private key removed from filesystem

### Step 32: Create Inventories and Repository

**What happens:**
1. **Create inventories:**
   - Function: `create_default_inventory()` (semaphore-api.sh:998)
   - Detects VM IP: `hostname -I | awk '{print $1}'` (typically `10.10.20.10`)
   - Fallback: Uses `STATIC_IP` from config if detection fails

2. **Create container-host inventory:**
   - Inventory name: "container-host"
   - SSH key ID: 2 (VM self-management key from step 31)
   - Content (YAML):
     ```yaml
     all:
       hosts:
         container-host:
           ansible_host: 10.10.20.10
           ansible_user: debian
           ansible_become: true
           ansible_become_method: sudo
     ```
   - API endpoint: `POST https://localhost:2443/api/project/1/inventory`
   - Payload includes inventory content and SSH key ID
   - Response: Inventory ID (typically `1`)

3. **Create localhost inventory:**
   - Inventory name: "localhost"
   - SSH key ID: none (uses ansible_connection: local)
   - Content (YAML):
     ```yaml
     all:
       hosts:
         localhost:
           ansible_connection: local
     ```
   - API endpoint: `POST https://localhost:2443/api/project/1/inventory`
   - Response: Inventory ID (typically `2`)

4. **Create Proxmox inventory (conditional):**
   - Checks for: `/etc/privatebox-proxmox-host` file
   - Reads Proxmox IP from file (typically `192.168.1.10`)
   - Looks up Proxmox SSH key by name "proxmox"
   - Inventory name: "proxmox"
   - Content (YAML):
     ```yaml
     all:
       hosts:
         proxmox:
           ansible_host: 192.168.1.10
           ansible_user: root
     ```
   - API endpoint: `POST https://localhost:2443/api/project/1/inventory`
   - Response: Inventory ID (typically `3`)

5. **Create repository:**
   - Function: `create_repository()` (semaphore-api.sh:35)
   - Progress marker: `PROGRESS:Creating repository` → `/etc/privatebox-install-complete`
   - Repository name: "PrivateBox"
   - Git URL: `https://github.com/Rasped/privatebox`
   - Git branch: "main"
   - SSH key ID: 1 (uses first SSH key by default)
   - API endpoint: `POST https://localhost:2443/api/project/1/repositories`
   - Payload:
     ```json
     {
       "name": "PrivateBox",
       "project_id": 1,
       "git_url": "https://github.com/Rasped/privatebox",
       "git_branch": "main",
       "ssh_key_id": 1
     }
     ```
   - Response: Repository ID (typically `1`)

**API calls:**
- `POST https://localhost:2443/api/project/1/inventory` (container-host)
- `POST https://localhost:2443/api/project/1/inventory` (localhost)
- `GET https://localhost:2443/api/project/1/keys` (lookup Proxmox key)
- `POST https://localhost:2443/api/project/1/inventory` (proxmox)
- `POST https://localhost:2443/api/project/1/repositories`

**BoltDB changes:**
- 3 inventory records created
- 1 repository record created

**State after step:**
- Inventories configured for VM, localhost, and Proxmox
- Repository linked to GitHub

### Step 33: Create Environments (Passwords and Proxmox API)

**What happens:**
1. **Progress marker:**
   - Writes: `PROGRESS:Creating environments` → `/etc/privatebox-install-complete`

2. **Create ServicePasswords environment:**
   - Function: `create_password_environment()` (semaphore-api.sh:402)
   - Environment name: "ServicePasswords"
   - API endpoint: `POST https://localhost:2443/api/project/1/environment`
   - Payload:
     ```json
     {
       "name": "ServicePasswords",
       "project_id": 1,
       "json": "{}",
       "env": "{}",
       "secrets": [
         {
           "type": "var",
           "name": "ADMIN_PASSWORD",
           "secret": "<5-word phonetic password from step 10>",
           "operation": "create"
         },
         {
           "type": "var",
           "name": "SERVICES_PASSWORD",
           "secret": "<3-word phonetic password from step 10>",
           "operation": "create"
         }
       ]
     }
     ```
   - Response: Environment ID (typically `1`)
   - These passwords are used for service authentication

3. **Create ProxmoxAPI environment:**
   - Function: `create_proxmox_api_environment()` (semaphore-api.sh:287)
   - Environment name: "ProxmoxAPI"
   - Reads values from config:
     - `PROXMOX_TOKEN_ID` (from step 10): "automation@pve!ansible"
     - `PROXMOX_TOKEN_SECRET` (from step 10): generated token
     - `PROXMOX_API_HOST`: "192.168.1.10"
     - `PROXMOX_NODE`: hostname (e.g., "pve")
   - API endpoint: `POST https://localhost:2443/api/project/1/environment`
   - Payload:
     ```json
     {
       "name": "ProxmoxAPI",
       "project_id": 1,
       "json": "{\"PROXMOX_NODE\":\"pve\"}",
       "env": "{}",
       "secrets": [
         {
           "type": "var",
           "name": "PROXMOX_API_HOST",
           "secret": "192.168.1.10",
           "operation": "create"
         },
         {
           "type": "var",
           "name": "PROXMOX_TOKEN_ID",
           "secret": "automation@pve!ansible",
           "operation": "create"
         },
         {
           "type": "var",
           "name": "PROXMOX_TOKEN_SECRET",
           "secret": "<token from step 10>",
           "operation": "create"
         }
       ]
     }
     ```
   - Response: Environment ID (typically `2`)

**API calls:**
- `POST https://localhost:2443/api/project/1/environment` (ServicePasswords)
- `POST https://localhost:2443/api/project/1/environment` (ProxmoxAPI)

**BoltDB changes:**
- 2 environment records created with encrypted secrets

**State after step:**
- ServicePasswords environment (ID 1): ADMIN_PASSWORD, SERVICES_PASSWORD
- ProxmoxAPI environment (ID 2): Proxmox API credentials

### Step 34: Template Synchronization Setup

**What happens:**
1. **Initialize template sync:**
   - Function: `setup_template_synchronization()` (semaphore-api.sh:474)
   - Progress marker: `PROGRESS:Setting up template synchronization` → `/etc/privatebox-install-complete`
   - This is a 7-step process (Steps 1-7 shown in logs)

2. **Step 1/6: Create API token:**
   - Function: `create_api_token()` (semaphore-api.sh:89)
   - Token name: "template-generator"
   - API endpoint: `POST https://localhost:2443/api/user/tokens`
   - Payload:
     ```json
     {
       "name": "template-generator"
     }
     ```
   - Response contains token ID/value (e.g., "abc123...")
   - This token allows Python scripts to call Semaphore API

3. **Step 2/6: Create SemaphoreAPI environment:**
   - Function: `create_semaphore_api_environment()` (semaphore-api.sh:120)
   - Environment name: "SemaphoreAPI"
   - Detects VM IP dynamically: `hostname -I | awk '{print $1}'`
   - API endpoint: `POST https://localhost:2443/api/project/1/environment`
   - Payload:
     ```json
     {
       "name": "SemaphoreAPI",
       "project_id": 1,
       "json": "{\"SEMAPHORE_URL\":\"https://10.10.20.10:2443\"}",
       "env": "{}",
       "secrets": [
         {
           "type": "var",
           "name": "SEMAPHORE_API_TOKEN",
           "secret": "<token from step 1>",
           "operation": "create"
         }
       ]
     }
     ```
   - Response: Environment ID (typically `3`)
   - Used by Python tools to access Semaphore API

4. **Step 3/6: Use default resource IDs:**
   - Repository ID: 1 (created in step 32)
   - Inventory ID: 1 (localhost inventory from step 32)
   - These are used for running Python tasks

5. **Step 4/7: Create Generate Templates task:**
   - Function: `create_template_generator_task()` → `create_python_template()` (semaphore-api.sh:269, 199)
   - Template name: "Generate Templates"
   - Playbook path: "tools/generate-templates.py"
   - Description: "Automatically generate Semaphore templates from playbooks"
   - API endpoint: `POST https://localhost:2443/api/project/1/templates`
   - Payload:
     ```json
     {
       "name": "Generate Templates",
       "project_id": 1,
       "inventory_id": 1,
       "repository_id": 1,
       "environment_id": 3,
       "app": "python",
       "playbook": "tools/generate-templates.py",
       "description": "Automatically generate Semaphore templates from playbooks",
       "arguments": "[]",
       "allow_override_args_in_task": false,
       "type": ""
     }
     ```
   - Response: Template ID (typically `1`)
   - This Python script reads playbooks and creates Semaphore templates via API

6. **Step 5/7: Create Orchestrate Services task:**
   - Function: `create_orchestrate_services_task()` → `create_python_template()` (semaphore-api.sh:278, 199)
   - Template name: "Orchestrate Services"
   - Playbook path: "tools/orchestrate-services.py"
   - Description: "Orchestrate OPNsense and AdGuard service deployment"
   - API endpoint: `POST https://localhost:2443/api/project/1/templates`
   - Payload structure same as Generate Templates, different name/path
   - Response: Template ID (typically `2`)
   - This Python script orchestrates service deployment in correct order

7. **Step 6/7: Run Generate Templates task:**
   - Function: `run_generate_templates_task()` (semaphore-api.sh:638)
   - Progress marker: `PROGRESS:Generating service templates` → `/etc/privatebox-install-complete`
   - API endpoint: `POST https://localhost:2443/api/project/1/tasks`
   - Payload:
     ```json
     {
       "template_id": 1,
       "debug": false,
       "dry_run": false
     }
     ```
   - Response contains task ID (e.g., `1`)
   - This executes the Python script inside Semaphore container

8. **Wait for Generate Templates completion:**
   - Function: `wait_for_task_completion()` (polls task status)
   - API endpoint (status): `GET https://localhost:2443/api/project/1/tasks/1`
   - Poll interval: varies by implementation
   - Timeout: 120 seconds
   - Checks task status until "success" or "error"
   - **What the Python script does:**
     - Clones repository to `/projects/privatebox`
     - Scans `ansible/playbooks/services/*/semaphore.yml` for service definitions
     - For each service, creates Semaphore template via API
     - Creates templates like "AdGuard 1: Deploy", "OPNsense 1: Deploy VM", etc.
     - Uses SemaphoreAPI environment to authenticate

**API calls:**
- `POST https://localhost:2443/api/user/tokens` (create API token)
- `POST https://localhost:2443/api/project/1/environment` (SemaphoreAPI env)
- `POST https://localhost:2443/api/project/1/templates` (Generate Templates)
- `POST https://localhost:2443/api/project/1/templates` (Orchestrate Services)
- `POST https://localhost:2443/api/project/1/tasks` (run Generate Templates)
- `GET https://localhost:2443/api/project/1/tasks/1` (poll status, repeated)

**BoltDB changes:**
- API token record created
- SemaphoreAPI environment (ID 3) created
- 2 template records created (Generate Templates, Orchestrate Services)
- Task execution record created
- **Additional templates created by Python script:**
  - Service deployment templates (varies by repository content)
  - Example: "AdGuard 1: Deploy", "AdGuard 2: Configure", etc.

**Files created:**
- `/projects/privatebox/` (repository cloned inside Semaphore container)

**State after step:**
- Template generator configured and executed
- Service templates auto-generated in Semaphore
- Ready for service orchestration

### Step 35: Service Orchestration and Deployment

**What happens:**
1. **Step 7/7: Run service orchestration:**
   - Function: `run_service_orchestration()` (semaphore-api.sh:825)
   - Progress marker: `PROGRESS:Running service orchestration` → `/etc/privatebox-install-complete`

2. **Find Orchestrate Services template:**
   - Function: `get_template_id_by_name()` (semaphore-api.sh:614)
   - Template name: "Orchestrate Services"
   - API endpoint: `GET https://localhost:2443/api/project/1/templates`
   - Searches response for matching name
   - Returns template ID (typically `2`)

3. **Start orchestration task:**
   - API endpoint: `POST https://localhost:2443/api/project/1/tasks`
   - Payload:
     ```json
     {
       "template_id": 2,
       "debug": false,
       "dry_run": false
     }
     ```
   - Response: Task ID (e.g., `2`)
   - Executes `tools/orchestrate-services.py` inside Semaphore container

4. **Monitor orchestration with progress streaming:**
   - Function: `wait_for_orchestration_with_progress()` (semaphore-api.sh:720)
   - Timeout: 1200 seconds (20 minutes)
   - Poll interval: 10 seconds

5. **Progress monitoring loop:**
   - API endpoint (status): `GET https://localhost:2443/api/project/1/tasks/2`
   - API endpoint (output): `GET https://localhost:2443/api/project/1/tasks/2/output`
   - Output format: JSON array of log lines
     ```json
     [
       {"task_id": 2, "time": "...", "output": "→ Executing: OPNsense 1: Deploy VM"},
       {"task_id": 2, "time": "...", "output": "  ✓ OPNsense 1: Deploy VM completed successfully"},
       ...
     ]
     ```

6. **Parse progress markers from output:**
   - Detects lines matching: `^→ Executing: (.+)`
     - Extracts template name being executed
     - Logs: `→ AdGuard 1: Deploy`
     - Writes: `PROGRESS:Deploying AdGuard 1: Deploy` → `/etc/privatebox-install-complete`
   - Detects lines matching: `^\s+✓ (.+) completed successfully`
     - Logs completion: `✓ AdGuard 1: Deploy`
   - Detects lines matching: `^\s+✗`
     - Logs errors/warnings

7. **What orchestrate-services.py does:**
   - Reads service definitions from repository
   - Determines deployment order (dependencies)
   - Executes templates sequentially:
     1. **OPNsense deployment** (if configured):
        - Template: "OPNsense 1: Deploy VM"
        - Creates VM at 10.10.20.1
        - Configures as network gateway
     2. **AdGuard deployment:**
        - Template: "AdGuard 1: Deploy"
        - Deploys as Podman container at 10.10.20.10:53
        - Template: "AdGuard 2: Configure"
        - Configures blocklists (OISD Basic + Steven Black)
        - Sets upstream DNS to Quad9
     3. **Additional services** (if defined)
   - Reports progress via stdout (captured by Semaphore)

8. **Wait for task completion:**
   - Checks task status on each poll
   - Status values: "running", "success", "error", "failed"
   - On success: logs service URLs and returns 0
   - On error: displays last 5 output lines and returns 1

9. **On successful completion:**
   - Logs deployed services:
     ```
     ✓ All services deployed successfully
       OPNsense firewall: 10.10.20.1
       AdGuard DNS: 10.10.20.10:53
       AdGuard web UI: https://adguard.lan
       PrivateBox dashboard: https://privatebox.lan
     ```
   - Progress marker: `PROGRESS:All services deployed successfully` → `/etc/privatebox-install-complete`

**API calls (monitoring):**
- `GET https://localhost:2443/api/project/1/templates` (find Orchestrate Services)
- `POST https://localhost:2443/api/project/1/tasks` (start orchestration)
- `GET https://localhost:2443/api/project/1/tasks/2` (status checks, repeated every 10s)
- `GET https://localhost:2443/api/project/1/tasks/2/output` (output streaming, repeated every 10s)

**API calls (from orchestrate-services.py):**
- Multiple `POST https://localhost:2443/api/project/1/tasks` (one per service template)
- Multiple `GET https://localhost:2443/api/project/1/tasks/<id>` (monitor each service deployment)

**Services deployed:**
- OPNsense firewall VM (10.10.20.1) - network gateway
- AdGuard DNS container (10.10.20.10:53) - DNS filtering
- AdGuard web UI (10.10.20.10:8080) - management interface
- Homer dashboard (10.10.20.10:8081) - service overview

**BoltDB changes:**
- Orchestration task record created
- Multiple task records for each service deployment

**State after step:**
- All services deployed and configured
- Network infrastructure operational
- DNS filtering active

**Control returns to:** `setup-guest.sh` for final cleanup

---

## Phase 4 Summary

**What Phase 4 accomplished:**
1. Installed system packages and Podman runtime (steps 18-19)
2. Built custom Semaphore image with Proxmox support (step 21)
3. Configured and started Portainer + Semaphore containers (steps 22-26)
4. Created Semaphore admin user via direct database access (step 27)
5. Generated VM SSH key for self-management (step 28)
6. Configured Semaphore via API (steps 29-33):
   - Created PrivateBox project
   - Uploaded SSH keys (Proxmox + VM)
   - Created inventories (localhost, container-host, proxmox)
   - Created repository link to GitHub
   - Created environments (passwords, Proxmox API, Semaphore API)
7. Generated service templates via Python script (step 34)
8. Deployed all services via orchestration (step 35)

**Final state:**
- Management VM: 10.10.20.10
  - Portainer: https://portainer.lan
  - Semaphore: https://semaphore.lan
  - AdGuard web UI: https://adguard.lan
  - PrivateBox dashboard: https://privatebox.lan
- Network infrastructure:
  - OPNsense gateway: 10.10.20.1
  - AdGuard DNS: 10.10.20.10:53 → Quad9 → Unbound fallback
- All services running and configured
- Semaphore has complete infrastructure management capabilities

**Next:** Installation completion and verification (setup-guest.sh final steps)

