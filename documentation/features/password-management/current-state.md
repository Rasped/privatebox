# Password Management - Current State

## Overview
This document captures the current state of password management in PrivateBox bootstrap and the target behavior we want to achieve.

## Current State (As of 2025-08-02)

### Password Generation
- **VM Password**: Hardcoded to `"Changeme123"` in multiple places:
  - `create-ubuntu-vm.sh:108`: Default value
  - `create-ubuntu-vm.sh:121`: Override default
  - `network-discovery.sh:371`: Config template
  - `privatebox-deploy.sh:78`: Deployment script

- **Semaphore Admin Password**: Randomly generated each time:
  - `create-ubuntu-vm.sh:125`: `SEMAPHORE_ADMIN_PASSWORD=$(generate_password)`
  - `semaphore-credentials-boltdb.sh:61`: Generates if not set
  - Saved to config file after generation

- **MySQL Passwords**: Generated for Semaphore database:
  - `semaphore-credentials.sh:58-59`: Root and semaphore user passwords

- **Portainer**: No admin user creation in current implementation

### Configuration File
- **Location**: `bootstrap/config/privatebox.conf`
- **Template**: `bootstrap/config/privatebox.conf.example`
- **Password Fields**: Currently none in template
- **Loading**: Scripts source the config but passwords aren't defined there

### Password Propagation Flow
```
1. network-discovery.sh creates privatebox.conf (no passwords)
2. create-ubuntu-vm.sh sources config
3. VM_PASSWORD defaults to "Changeme123" (ignores config)
4. SEMAPHORE_ADMIN_PASSWORD generated randomly
5. Passwords passed to cloud-init:
   - VM user: plain_text_passwd: ${VM_PASSWORD}
   - Semaphore: Written to /etc/privatebox-semaphore-password
6. Services read passwords:
   - Semaphore reads from file or generates new one
   - No coordination between services
```

### Storage Locations
- **During Bootstrap**:
  - `/etc/privatebox-semaphore-password` (in VM)
  - `/root/.credentials/semaphore_credentials.txt` (in VM)
  
- **No Persistent Storage**: Passwords only exist in memory and temporary files

### Issues with Current Approach
1. **Inconsistent Passwords**: Each service has different passwords
2. **No Config Integration**: Config file exists but doesn't define passwords
3. **Hardcoded Defaults**: "Changeme123" scattered throughout code
4. **Random Generation**: Semaphore password different each run
5. **No Proxmox Integration**: No way to set Proxmox root password
6. **No Update Mechanism**: Can't change passwords after deployment

## Target Behavior

### Password Strategy
Two master passwords for different security contexts:

1. **ADMIN_PASSWORD** (Infrastructure)
   - Purpose: High-privilege infrastructure access
   - Used for:
     - Proxmox root account
     - VM root accounts
     - Future infrastructure VMs (OPNsense, etc.)
   - Complexity: High (special chars, length 20+)

2. **SERVICES_PASSWORD** (Services)
   - Purpose: Daily web UI access
   - Used for:
     - VM regular user (ubuntuadmin)
     - Semaphore admin UI
     - Portainer admin UI
     - AdGuard admin UI
     - Other service UIs
   - Complexity: Moderate (easier to type)

### Configuration Integration
```bash
# In privatebox.conf
ADMIN_PASSWORD="Complex#Infrastructure@2024!"
SERVICES_PASSWORD="ServicesDaily123"
```

### Propagation Flow
```
1. User creates privatebox.conf with both passwords
2. Bootstrap reads and validates passwords
3. Passwords propagated to:
   - Cloud-init (both passwords)
   - All service configurations
   - Secure storage for Ansible
4. Config file deleted after successful bootstrap
```

### Secure Storage
```
/opt/privatebox/secrets/
├── admin-password      # chmod 600, root only
└── services-password   # chmod 600, root only
```

### Password Update Capability
- Ansible playbook to update all service passwords
- Reads from secure storage
- Updates all services in coordination

## Implementation Requirements

### Phase 1: Bootstrap Integration
1. Add password fields to config template
2. Update config_manager.sh to handle passwords
3. Modify create-ubuntu-vm.sh to use config passwords
4. Update all services to use consistent passwords
5. Add password validation and generation fallback

### Phase 2: Secure Storage
1. Create secure storage during bootstrap
2. Save passwords before config deletion
3. Update Ansible playbooks to read from storage
4. Implement password rotation playbook

### Security Considerations
- Config file must be chmod 600
- Passwords cleared from environment after use
- Secure storage only readable by root
- No passwords in logs or command history
- Warning messages about removing config file