# PrivateBox Ansible Automation

This directory contains Ansible automation for deploying containerized services on PrivateBox using Podman Quadlet.

## Overview

This implementation uses a **service-oriented approach** where each container service has its own dedicated playbook. This design is optimized for use with SemaphoreUI and prioritizes simplicity and maintainability.

## Directory Structure

```
ansible/
├── inventories/          # Host inventories
│   ├── development/      # Development environment
│   └── production/       # Production environment
├── group_vars/          # Variable definitions
│   ├── all/             # Global variables
│   └── privatebox/      # PrivateBox-specific variables
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
3. SSH access to target hosts

### Deploy AdGuard Home

```bash
# Using ansible-playbook directly
ansible-playbook -i inventories/development/hosts.yml playbooks/services/adguard.yml

# Or configure in SemaphoreUI as a job template
```

### Deploy via SemaphoreUI

1. Create a new job template in SemaphoreUI
2. Set playbook to `playbooks/services/adguard.yml`
3. Select appropriate inventory
4. Configure survey variables:
   - `confirm_deploy`: Boolean (default: yes)
   - `custom_web_port`: Integer (default: 8080)

## Available Services

### Implemented

- **AdGuard Home** (`playbooks/services/adguard.yml`) - DNS-level ad blocking

### Planned

- **Pi-hole** - Alternative DNS ad blocker
- **Unbound** - Recursive DNS resolver
- **WireGuard** - VPN server
- **Nginx Proxy Manager** - Reverse proxy with GUI

## Configuration

### Global Settings

Edit `group_vars/all/main.yml` and `group_vars/all/containers.yml` for global configuration.

### Service-Specific Settings

Edit `group_vars/privatebox/main.yml` to configure individual services:

```yaml
# Enable/disable services
enable_adguard: true
enable_pihole: false

# AdGuard configuration
adguard_web_port: 8080
adguard_dns_port: 53
adguard_memory_limit: "512M"
```

### Environment-Specific Settings

- Development: `inventories/development/hosts.yml`
- Production: `inventories/production/hosts.yml`

## Adding New Services

1. **Copy the template playbook**:
   ```bash
   cp playbooks/services/_template.yml playbooks/services/newservice.yml
   ```

2. **Create a Quadlet template**:
   ```bash
   cp files/quadlet/_template.container.j2 files/quadlet/newservice.container.j2
   ```

3. **Update variables** in `group_vars/privatebox/main.yml`:
   ```yaml
   # New Service Configuration
   newservice_enabled: true
   newservice_image: "vendor/newservice"
   newservice_version: "latest"
   newservice_port: 8082
   newservice_data_dir: "{{ container_data_root }}/newservice"
   ```

4. **Edit the playbook** and template with service-specific details

5. **Test deployment**:
   ```bash
   ansible-playbook -i inventories/development/hosts.yml playbooks/services/newservice.yml
   ```

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

See `group_vars/all/containers.yml` for:
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

1. Check service status:
   ```bash
   ansible privatebox -i inventories/development/hosts.yml -m systemd -a "name=adguard-container"
   ```

2. Verify container is running:
   ```bash
   ansible privatebox -i inventories/development/hosts.yml -m command -a "podman ps"
   ```

3. Test service endpoint:
   ```bash
   curl -I http://<host-ip>:8080
   ```

### Automated Testing

See `documentation/features/ansible-container-services/testing.md` for comprehensive testing strategy.

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

Run playbooks with increased verbosity:
```bash
ansible-playbook -i inventories/development/hosts.yml playbooks/services/adguard.yml -vvv
```

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