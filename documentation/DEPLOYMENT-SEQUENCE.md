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

