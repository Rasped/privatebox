# PrivateBox Bootstrap Execution Flow

This document maps out the complete order of script execution during PrivateBox bootstrap.

## Overview

The bootstrap process consists of 5 phases, starting from a workstation and culminating in a fully deployed management VM with services.

**Key Points:**
- **Generate Templates is called TWICE:** once before orchestration, once during (step 8/13)
- **13-step orchestration** deploys all services in dependency order
- **Subnet Router** requires 3-step process (deploy Debian VM, configure, approve routes)
- **Portainer** is deployed first, before other services
- **Caddy** is deployed last as reverse proxy for .lan domain access
- **All 13 playbooks** are deployed automatically (11 Ansible playbooks + 1 Python script called twice)

---

## Execution Flow

### Entry Point: Workstation

**1. quickstart.sh**
- **Location:** Repository root
- **Executed from:** User's workstation via `curl | bash`
- **Runs on:** Proxmox host (via SSH)
- **Purpose:** Download repository and initiate bootstrap

**Actions:**
- Runs preflight checks (root, Proxmox, dependencies)
- Fixes Proxmox repository configuration
- Clones repository to `/tmp/privatebox-quickstart`
- Calls → `bootstrap/bootstrap.sh`

---

### Main Orchestrator: Proxmox Host

**2. bootstrap/bootstrap.sh**
- **Location:** `bootstrap/bootstrap.sh`
- **Executed from:** quickstart.sh
- **Runs on:** Proxmox host
- **Purpose:** Main orchestrator for all bootstrap phases

---

#### Phase 1: Host Preparation

**3. prepare-host.sh**
- **Location:** `bootstrap/prepare-host.sh`
- **Called by:** bootstrap.sh Phase 1
- **Runs on:** Proxmox host
- **Purpose:** Detect network, generate config, verify environment

**Actions:**
- Detects network topology (gateway, bridge)
- Generates passwords (admin, services)
- Creates Proxmox API token (optional)
- Verifies storage availability
- Writes → `/tmp/privatebox-config.conf`

**Output:** Configuration file with network settings and credentials

---

#### Phase 2: OPNsense Deployment

**4. deploy-opnsense.sh**
- **Location:** `bootstrap/deploy-opnsense.sh`
- **Called by:** bootstrap.sh Phase 2
- **Runs on:** Proxmox host
- **Purpose:** Deploy OPNsense firewall VM from template

**Actions:**
- Downloads OPNsense template from GitHub
- Creates VM 1000 from template
- Configures network interfaces (WAN/LAN)
- Starts firewall VM

**Output:** Running OPNsense VM at 10.10.20.1

---

#### Phase 3: Management VM Provisioning

**5. create-vm.sh**
- **Location:** `bootstrap/create-vm.sh`
- **Called by:** bootstrap.sh Phase 3
- **Runs on:** Proxmox host
- **Purpose:** Create and configure management VM with cloud-init

**Actions:**
- Downloads Debian 13 cloud image
- Generates SSH keys (Proxmox host ↔ VM)
- Generates self-signed HTTPS certificate
- **Embeds scripts into cloud-init:**
  - `bootstrap/setup-guest.sh` → `/usr/local/bin/setup-guest.sh`
  - `bootstrap/lib/semaphore-api.sh` → `/usr/local/lib/semaphore-api.sh`
  - `bootstrap/lib/password-generator.sh` → `/usr/local/lib/password-generator.sh`
  - `/tmp/privatebox-config.conf` → `/etc/privatebox/config.env`
  - HTTPS cert/key → `/etc/privatebox/certs/`
- Creates VM 9000 with cloud-init
- Configures static IP (10.10.20.10)
- Starts VM

**Output:** Running Debian VM ready for Phase 4 (cloud-init execution)

---

#### Phase 4: Service Configuration (Inside VM)

**6. setup-guest.sh** (via cloud-init)
- **Location:** Embedded in cloud-init by create-vm.sh
- **Called by:** Cloud-init runcmd
- **Runs on:** Management VM (inside guest)
- **Purpose:** Install services and bootstrap Semaphore

**Actions:**
1. System package installation
   - Updates/upgrades Debian packages
   - Installs: curl, wget, jq, git, podman, buildah, skopeo

2. Podman configuration
   - Enables Podman socket (Docker API compatibility)
   - Creates directories for Semaphore

3. HTTPS certificate verification
   - Verifies cert files written by cloud-init

4. Custom Semaphore image build
   - Writes Containerfile extending semaphoreui/semaphore:latest
   - Adds Python packages: proxmoxer, requests
   - Builds → `localhost/semaphore-proxmox:latest`

5. Semaphore configuration
   - Generates config.json with TLS settings
   - Creates Quadlet systemd unit
   - Enables nightly image rebuild timer

6. Service startup
   - Starts Semaphore service
   - Waits for API readiness
   - Creates admin user via container exec

7. **Semaphore API Bootstrap** (sources lib/semaphore-api.sh)
   - Calls → `create_default_projects()`

**Progress markers written to:** `/etc/privatebox-install-complete`

---

#### Phase 4 (continued): Semaphore API Bootstrap

**7. lib/semaphore-api.sh functions** (sourced by setup-guest.sh)
- **Location:** Embedded in cloud-init, placed at `/usr/local/lib/semaphore-api.sh`
- **Called by:** setup-guest.sh
- **Runs on:** Management VM
- **Purpose:** Configure Semaphore via API and deploy services

**Function Call Chain:**

```
create_default_projects()
  ├─→ wait_for_semaphore_api()
  │    └─→ Polls https://localhost:2443/api/ping
  │
  ├─→ get_admin_session()
  │    └─→ Returns session cookie for API auth
  │
  └─→ create_infrastructure_project_with_ssh_key()
       ├─→ Creates "PrivateBox" project
       ├─→ Uploads SSH keys (proxmox, container-host)
       ├─→ create_default_inventory()
       │    ├─→ Creates "localhost" inventory
       │    ├─→ Creates "container-host" inventory (VM self-management)
       │    └─→ Creates "proxmox" inventory (if API token available)
       ├─→ create_repository()
       │    └─→ Adds GitHub repo: https://github.com/Rasped/privatebox.git
       ├─→ create_password_environment()
       │    └─→ Creates "ServicePasswords" env with ADMIN_PASSWORD, SERVICES_PASSWORD
       ├─→ create_proxmox_api_environment()
       │    └─→ Creates "ProxmoxAPI" env with token credentials (if available)
       │
       └─→ setup_template_synchronization()
            ├─→ create_api_token()
            │    └─→ Generates Semaphore API token for template-generator
            │
            ├─→ create_semaphore_api_environment()
            │    └─→ Creates "SemaphoreAPI" env with SEMAPHORE_URL, SEMAPHORE_API_TOKEN
            │
            ├─→ create_template_generator_task()
            │    └─→ Creates "Generate Templates" task → tools/generate-templates.py
            │
            ├─→ create_orchestrate_services_task()
            │    └─→ Creates "Orchestrate Services" task → tools/orchestrate-services.py
            │
            ├─→ run_generate_templates_task()
            │    ├─→ Triggers "Generate Templates" via Semaphore API
            │    │    └─→ [Semaphore runs Python script inside container]
            │    └─→ wait_for_task_completion()
            │
            └─→ run_service_orchestration()
                 ├─→ Triggers "Orchestrate Services" via Semaphore API
                 │    └─→ [Semaphore runs Python orchestrator inside container]
                 │         └─→ Calls "Generate Templates" AGAIN (step 8/12)
                 └─→ wait_for_orchestration_with_progress()
                      └─→ Streams real-time progress from Semaphore API
```

---

#### Phase 4 (continued): Python Orchestration

**8. tools/generate-templates.py** (via Semaphore container)
- **Location:** `tools/generate-templates.py`
- **Triggered by:** `run_generate_templates_task()` via Semaphore API
- **Runs in:** Semaphore container
- **Purpose:** Auto-generate Semaphore templates from Ansible playbooks

**Actions:**
- Scans `ansible/playbooks/**/*.yml` for playbooks
- Reads YAML front-matter metadata (vars_prompt with semaphore_* fields)
- Creates Semaphore templates via API for each playbook
- Templates include:
  - Name, description
  - Repository, inventory, environment references
  - Ansible vars_prompt converted to Semaphore survey fields

**Output:** Semaphore templates for all service playbooks

---

**9. tools/orchestrate-services.py** (via Semaphore container)
- **Location:** `tools/orchestrate-services.py`
- **Triggered by:** `run_service_orchestration()` via Semaphore API
- **Runs in:** Semaphore container
- **Purpose:** Deploy services in correct dependency order

**Execution Order (13 steps):**

1. **Portainer 1: Deploy Container Management UI**
   - Playbook: `ansible/playbooks/services/portainer-deploy.yml`
   - Purpose: Deploy Podman/Docker management UI
   - Target: Management VM (container-host)

2. **AdGuard 1: Deploy Container Service**
   - Playbook: `ansible/playbooks/services/adguard-deploy.yml`
   - Purpose: Deploy DNS filtering service
   - Target: Management VM (container-host)

3. **OPNsense 1: Configure Secure Access**
   - Playbook: `ansible/playbooks/services/opnsense-secure-access.yml`
   - Purpose: Configure secure management access to firewall
   - Target: OPNsense VM (10.10.20.1)

4. **OPNsense 2: Configure Semaphore Integration**
   - Playbook: `ansible/playbooks/services/opnsense-semaphore-integration.yml`
   - Purpose: Configure Semaphore API access to OPNsense
   - Target: OPNsense VM (10.10.20.1)

5. **OPNsense 3: Apply Post-Configuration**
   - Playbook: `ansible/playbooks/services/opnsense-post-config.yml`
   - Purpose: Configure firewall rules, VLANs, NAT
   - Target: OPNsense VM (10.10.20.1)

6. **Headscale 1: Deploy VPN Control Server**
   - Playbook: `ansible/playbooks/services/headscale-deploy.yml`
   - Purpose: Deploy VPN coordination server
   - Target: Management VM (container-host)

7. **Subnet Router 1: Create Debian VM** (playbook name says "Alpine" but uses Debian!)
   - Playbook: `ansible/playbooks/infrastructure/subnet-router-deploy.yml`
   - Purpose: Create Debian 13 VM for VPN subnet routing
   - Target: Proxmox (via API from localhost)
   - OS: Debian 13 cloud image (same as management VM)

8. **Generate Templates** (called AGAIN - 2nd time!)
   - Script: `tools/generate-templates.py`
   - Purpose: Re-scan playbooks to ensure subnet router templates exist
   - Why: New playbooks may have been added; ensures all templates available

9. **Subnet Router 2: Configure VPN Connection**
   - Playbook: `ansible/playbooks/infrastructure/subnet-router-configure.yml`
   - Purpose: Install Tailscale and connect to Headscale VPN
   - Target: Subnet Router VM (10.10.10.10)

10. **Subnet Router 3: Approve Routes**
    - Playbook: `ansible/playbooks/infrastructure/subnet-router-approve.yml`
    - Purpose: Approve subnet routes in Headscale
    - Target: Management VM (localhost - runs against Headscale API)

11. **Headplane 1: Deploy Headscale Web UI**
    - Playbook: `ansible/playbooks/services/headplane-deploy.yml`
    - Purpose: Deploy Headscale web management interface
    - Target: Management VM (container-host)

12. **Homer 1: Deploy Dashboard Service**
    - Playbook: `ansible/playbooks/services/homer-deploy.yml`
    - Purpose: Deploy service dashboard
    - Target: Management VM (container-host)

13. **Caddy 1: Deploy Reverse Proxy Service**
    - Playbook: `ansible/playbooks/services/caddy-deploy.yml`
    - Purpose: Deploy reverse proxy for .lan domain access
    - Target: Management VM (container-host)
    - Proxies: homer.lan, portainer.lan, semaphore.lan, adguard.lan, headplane.lan, opnsense.lan, proxmox.lan
    - Ports: 80 (HTTP), 443 (HTTPS)

**Actions for each service:**
- Finds template by name via Semaphore API
- Triggers template execution (creates task)
- Polls task status until completion
- Streams progress markers back to bootstrap.sh
- Fails fast on any service deployment error

**Output:** All services running and accessible via .lan domains

**Playbook Inventory (13 total):**

**Deployed automatically (12 playbooks):**
1. portainer-deploy.yml
2. adguard-deploy.yml
3. opnsense-secure-access.yml
4. opnsense-semaphore-integration.yml
5. opnsense-post-config.yml
6. headscale-deploy.yml
7. subnet-router-deploy.yml (Debian, not Alpine despite name)
8. subnet-router-configure.yml
9. subnet-router-approve.yml
10. headplane-deploy.yml
11. homer-deploy.yml
12. caddy-deploy.yml (NEW - added as final step)

**NOT deployed (manual/optional - 1 playbook):**
- `homer-update.yml` - For updating Homer config after initial deployment

---

#### Phase 5: Installation Verification

**10. verify-install.sh**
- **Location:** `bootstrap/verify-install.sh`
- **Called by:** bootstrap.sh Phase 5
- **Runs on:** Proxmox host
- **Purpose:** Verify successful installation and display access info

**Actions:**
- SSH into management VM
- Checks Semaphore service status
- Verifies Podman containers running
- Displays access URLs and credentials
- Writes completion markers

**Output:** Success message with service URLs

---

## Script Execution Context

| Script | Executed On | Execution Context | Triggered By |
|--------|-------------|-------------------|--------------|
| quickstart.sh | Proxmox host | Root shell | User (workstation) |
| bootstrap.sh | Proxmox host | Root shell | quickstart.sh |
| prepare-host.sh | Proxmox host | Root shell | bootstrap.sh |
| deploy-opnsense.sh | Proxmox host | Root shell | bootstrap.sh |
| create-vm.sh | Proxmox host | Root shell | bootstrap.sh |
| setup-guest.sh | Management VM | Cloud-init runcmd | Cloud-init |
| lib/semaphore-api.sh | Management VM | Bash (sourced) | setup-guest.sh |
| generate-templates.py | Semaphore container | Python | Semaphore API |
| orchestrate-services.py | Semaphore container | Python | Semaphore API |
| portainer-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| adguard-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| opnsense-*.yml (3 playbooks) | Semaphore container | Ansible | Semaphore (via orchestrator) |
| headscale-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| subnet-router-*.yml (3 playbooks) | Semaphore container | Ansible | Semaphore (via orchestrator) |
| generate-templates.py (2nd call) | Semaphore container | Python | orchestrate-services.py |
| headplane-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| homer-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| caddy-deploy.yml | Semaphore container | Ansible | Semaphore (via orchestrator) |
| verify-install.sh | Proxmox host | Root shell | bootstrap.sh |

---

## Visual Call Tree

```
[Workstation]
    │
    └─→ quickstart.sh (curl | bash)
           │
           ↓
    [Proxmox Host]
           │
           └─→ bootstrap/bootstrap.sh
                │
                ├─→ Phase 1: prepare-host.sh
                │    └─→ /tmp/privatebox-config.conf
                │
                ├─→ Phase 2: deploy-opnsense.sh
                │    └─→ VM 1000 (OPNsense)
                │
                ├─→ Phase 3: create-vm.sh
                │    ├─→ Embeds: setup-guest.sh
                │    ├─→ Embeds: lib/semaphore-api.sh
                │    ├─→ Embeds: lib/password-generator.sh
                │    └─→ VM 9000 (Management)
                │
                ├─→ Phase 4: [Cloud-init in VM]
                │    │
                │    └─→ [Management VM - via cloud-init]
                │         │
                │         └─→ setup-guest.sh
                │              ├─→ System setup
                │              ├─→ Podman + Semaphore install
                │              └─→ source lib/semaphore-api.sh
                │                   │
                │                   └─→ create_default_projects()
                │                        ├─→ Create project
                │                        ├─→ Create environments
                │                        ├─→ Create repositories
                │                        ├─→ Upload SSH keys
                │                        └─→ setup_template_synchronization()
                │                             │
                │                             ├─→ create_template_generator_task()
                │                             ├─→ create_orchestrate_services_task()
                │                             │
                │                             └─→ run_generate_templates_task()
                │                                  │
                │                                  ↓
                │                            [Semaphore Container]
                │                                  │
                │                                  ├─→ tools/generate-templates.py
                │                                  │    └─→ Scans ansible/playbooks/**/*.yml
                │                                  │         └─→ Creates Semaphore templates
                │                                  │
                │                                  └─→ run_service_orchestration()
                │                                       │
                │                                       └─→ tools/orchestrate-services.py (13 steps)
                │                                            ├─→ 1. portainer-deploy.yml
                │                                            ├─→ 2. adguard-deploy.yml
                │                                            ├─→ 3. opnsense-secure-access.yml
                │                                            ├─→ 4. opnsense-semaphore-integration.yml
                │                                            ├─→ 5. opnsense-post-config.yml
                │                                            ├─→ 6. headscale-deploy.yml
                │                                            ├─→ 7. subnet-router-deploy.yml (creates Debian VM)
                │                                            ├─→ 8. generate-templates.py (CALLED AGAIN!)
                │                                            ├─→ 9. subnet-router-configure.yml
                │                                            ├─→ 10. subnet-router-approve.yml
                │                                            ├─→ 11. headplane-deploy.yml
                │                                            ├─→ 12. homer-deploy.yml
                │                                            └─→ 13. caddy-deploy.yml (reverse proxy)
                │
                └─→ Phase 5: verify-install.sh
                     └─→ Display success + URLs
```

---

## Key Files and Their Locations

### Configuration Files (Generated)
- `/tmp/privatebox-config.conf` - Network and credential config (Proxmox host)
- `/etc/privatebox/config.env` - Same config, inside VM
- `/etc/privatebox-install-complete` - Progress marker file (VM)
- `/etc/privatebox-proxmox-host` - Proxmox IP for inventory creation (VM)

### Embedded Files (Written by cloud-init)
- `/usr/local/bin/setup-guest.sh` - Phase 4 main script
- `/usr/local/lib/semaphore-api.sh` - API interaction library
- `/etc/privatebox/certs/privatebox.{crt,key}` - Self-signed HTTPS cert

### SSH Keys
- `/root/.credentials/proxmox_ssh_key` - Semaphore → Proxmox (temporary, deleted after upload)
- `/root/.credentials/semaphore_vm_key` - Semaphore → VM self-management (retained)

### Service Data (Persistent)
- `/opt/semaphore/data` - Semaphore database
- `/opt/semaphore/config` - Semaphore config.json
- `/opt/semaphore/projects` - Playbook workspace

---

## Progress Markers

Throughout execution, scripts write progress markers to `/etc/privatebox-install-complete`:

```
PROGRESS:Starting guest configuration
PROGRESS:Updating system packages
PROGRESS:Building custom Semaphore image
PROGRESS:Starting Semaphore service
PROGRESS:Creating Semaphore admin user
PROGRESS:Configuring Semaphore API
PROGRESS:Creating PrivateBox project
PROGRESS:Uploading SSH keys
PROGRESS:Creating repository
PROGRESS:Creating environments
PROGRESS:Setting up template synchronization
PROGRESS:Generating service templates
PROGRESS:Running service orchestration
PROGRESS:Deploying OPNsense Post-Config
PROGRESS:Deploying AdGuard
PROGRESS:Deploying Homer
PROGRESS:All services deployed successfully
SUCCESS
```

These markers allow bootstrap.sh (Phase 5) to monitor progress in real-time.

---

## Error Handling

- Each script uses `set -euo pipefail` for fail-fast behavior
- Errors write `ERROR` to `/etc/privatebox-install-complete`
- bootstrap.sh monitors for ERROR status and fails if detected
- All API operations have retry logic (typically 3 attempts)
- Service orchestration fails fast on first service deployment error

---

## Notes

- Phase 4 orchestration is the longest phase due to sequential service deployments
- 13-step orchestration with 12 Ansible playbooks + 1 Python script (called twice)
- Generate Templates is called TWICE: once before orchestration, once during (step 8)
- All steps run sequentially with fail-fast on errors
