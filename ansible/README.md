# PrivateBox Ansible Automation

This directory contains Ansible automation for deploying containerized services on PrivateBox using Podman Quadlet.

## Overview

This implementation uses a **service-oriented approach** where each container service has its own dedicated playbook. This design is optimized for use with SemaphoreUI and prioritizes simplicity and maintainability.

### Self-Contained Playbooks

Each service playbook is completely self-contained:
- All variables are defined within the playbook (with sensible defaults)
- No dependency on external roles or includes
- Can be run independently without additional configuration
- Variables can be overridden via command line (-e flag)
- Designed for easy understanding and modification

## Directory Structure

```
ansible/
├── playbooks/           # Ansible playbooks
│   └── services/        # Service deployment playbooks
├── files/               # Static files
│   └── quadlet/         # Podman Quadlet templates
└── README.md            # This file
```

## Quick Start

### Prerequisites

1. PrivateBox VM created by bootstrap process
2. SemaphoreUI installed and configured
3. SSH keys configured in SemaphoreUI:
   - The bootstrap process creates two SSH keys:
     - **"proxmox"** - For managing the Proxmox host
     - **"container-host"** - For managing VMs and containers (use this one)
   - These keys are automatically added to SemaphoreUI
   - When creating job templates, select "container-host" from the SSH Key dropdown
4. SSH keys are automatically configured during bootstrap

### Deploy AdGuard Home

Services are deployed through SemaphoreUI job templates. The inventory is specified within each playbook.

## Automatic Template Synchronization

PrivateBox includes automatic template synchronization that creates Semaphore job templates from your Ansible playbooks. This eliminates the need to manually create templates in the Semaphore UI.

### How It Works

1. **Annotate Your Playbooks**: Add `semaphore_*` metadata to `vars_prompt` in your playbooks
2. **Run Template Sync**: Use the "Generate Templates" task in Semaphore (created during bootstrap)
   - Initial sync runs automatically during bootstrap setup
   - Run manually for new or updated playbooks
3. **Templates Are Created**: Semaphore automatically creates or updates job templates with proper survey variables

### Example Annotated Playbook

```yaml
vars_prompt:
  - name: confirm_deploy
    prompt: "Deploy AdGuard Home? (yes/no)"
    default: "yes"
    private: no
    # Semaphore metadata
    semaphore_type: boolean
    semaphore_description: "Confirm deployment of AdGuard Home"
    
  - name: custom_web_port
    prompt: "Web UI port"
    default: "8080"
    private: no
    semaphore_type: integer
    semaphore_description: "Port for AdGuard web interface"
    semaphore_min: 1024
    semaphore_max: 65535
    semaphore_required: false
```

### Supported Metadata Fields

- `semaphore_type`: Variable type (text, integer, boolean)
- `semaphore_description`: Help text shown in UI
- `semaphore_required`: Is field required? (default: true)
- `semaphore_min`: Minimum value (integer only)
- `semaphore_max`: Maximum value (integer only)

### Running Template Sync

1. Navigate to Task Templates in Semaphore UI
2. Click "Run" on "Generate Templates"
3. View the output to see which templates were created/updated

For a complete example, see `playbooks/services/test-semaphore-sync.yml`.

### Deploy via SemaphoreUI

You have two options:

#### Option 1: Use Automatically Generated Templates (Recommended)

If your playbook has `semaphore_*` metadata in `vars_prompt`:
1. Run the "Generate Templates" task to sync your playbooks
2. Find your automatically created template (e.g., "Deploy: adguard")
3. Click "Run" and fill in the survey variables

#### Option 2: Create Templates Manually

For playbooks without metadata or custom configurations:
1. Create a new job template in SemaphoreUI:
   - **Name**: "Deploy AdGuard Home"
   - **Playbook**: `playbooks/services/adguard.yml`
   - **Inventory**: Select your inventory
   - **Repository**: PrivateBox (already configured)
   - **Environment**: Select appropriate environment
   - **SSH Key**: Select "container-host" (created during bootstrap)
   
2. Configure survey variables:
   - `confirm_deploy`: Boolean (default: yes)
   - `custom_web_port`: Integer (default: 8080)
   
3. Save and run the job template

## Available Services

### Implemented

- **AdGuard Home** (`playbooks/services/adguard-deploy.yml`) - DNS-level ad blocking and filtering
- **AdGuard DNS Configuration** (`playbooks/services/adguard-configure-dns.yml`) - Configure system to use AdGuard DNS

### In Development

- **OPNsense FreeBSD Bootstrap** - New approach using FreeBSD cloud-init (see `documentation/features/opnsense-freebsd-bootstrap/`)

### Planned

- **Pi-hole** - Alternative DNS ad blocker
- **Unbound** - Recursive DNS resolver
- **WireGuard** - VPN server
- **Nginx Proxy Manager** - Reverse proxy with GUI

## Configuration

### Service Configuration

All service configuration is contained within each playbook. Variables have sensible defaults and can be overridden through Semaphore's survey variables when running job templates.


## Adding New Services

Each service playbook is self-contained, including all necessary variables, tasks, and configurations within a single file. This design prioritizes simplicity and maintainability.

1. **Create a new service playbook**:
   ```bash
   # Create your service playbook directly - no template needed
   vim playbooks/services/newservice.yml
   ```

2. **Create a Quadlet template**:
   ```bash
   cp files/quadlet/_template.container.j2 files/quadlet/newservice.container.j2
   ```

3. **Define variables** in your playbook:
   ```yaml
   vars:
     service_name: "New Service"
     newservice_image: "vendor/newservice"
     newservice_version: "latest"
     newservice_port: 8082
     newservice_data_dir: "/opt/privatebox/data/newservice"
   ```

4. **Edit the playbook** and template with service-specific details

5. **Add Semaphore metadata** to `vars_prompt` for automatic template generation:
   ```yaml
   vars_prompt:
     - name: confirm_deploy
       prompt: "Deploy New Service?"
       default: "yes"
       private: no
       # Add these for automatic template sync
       semaphore_type: boolean
       semaphore_description: "Confirm deployment of New Service"
   ```

6. **Sync to Semaphore**: Run "Generate Templates" to create the job template automatically

7. **Test deployment**: Run the job template through Semaphore UI

## Podman Quadlet

This project uses Podman Quadlet for systemd integration. Quadlet automatically generates systemd service units from `.container` files.

### Key Benefits

- Native systemd integration
- Automatic service management
- Better than docker-compose for single-host deployments
- Supports health checks and dependencies

### Service Management

```bash
# Check service status
sudo systemctl status adguard-container

# View logs
sudo podman logs adguard-home

# Restart service
sudo systemctl restart adguard-container

# Stop service
sudo systemctl stop adguard-container
```

## Variables Reference

### Container Defaults

Each playbook defines its own container settings:
- Container runtime settings
- Resource limits  
- Security defaults
- Network configuration

### Service Variables

Each service has variables following this pattern:
- `<service>_enabled` - Enable/disable service
- `<service>_image` - Container image
- `<service>_version` - Image version/tag
- `<service>_port` - Primary service port
- `<service>_data_dir` - Data persistence directory
- `<service>_config_dir` - Configuration directory
- `<service>_memory_limit` - Memory limit
- `<service>_cpu_quota` - CPU quota percentage

## Testing

### Manual Testing

After deploying a service:

1. SSH to the container host to check service status:
   ```bash
   sudo systemctl status adguard-container
   ```

2. Verify container is running:
   ```bash
   sudo podman ps
   ```

3. Test service endpoint:
   ```bash
   curl -I http://<host-ip>:8080
   ```

### Automated Testing

Testing is performed through Semaphore job templates. Create test playbooks and sync them using the template generation process.

## Troubleshooting

### Common Issues

1. **Port conflicts**: Check if ports are already in use
   ```bash
   sudo netstat -tlnp | grep <port>
   ```

2. **Podman not installed**: The AdGuard playbook will install it automatically

3. **SELinux issues**: Check SELinux context on data directories
   ```bash
   ls -laZ /opt/privatebox/data/
   ```

4. **Service won't start**: Check systemd logs
   ```bash
   sudo journalctl -u adguard-container -n 50
   ```

### Debug Mode

Enable verbose output in Semaphore job templates by adding `-vvv` to the CLI arguments field.

## Security Considerations

- Services run with `NoNewPrivileges=true`
- Capabilities are dropped by default
- SELinux contexts are set on data directories
- Each service runs in its own container namespace
- Avoid running services as root when possible

## Backup and Recovery

Container data is stored in:
- Data: `/opt/privatebox/data/<service>/`
- Config: `/opt/privatebox/config/<service>/`

Back up these directories to preserve service data.

## Contributing

When adding new services:
1. Follow the established pattern
2. Document all variables
3. Include health checks
4. Test on development first
5. Update this README

## Support

For issues or questions:
1. Check service logs: `sudo podman logs <container-name>`
2. Review systemd status: `sudo systemctl status <service>-container`
3. Consult the feature documentation in `documentation/features/ansible-container-services/`