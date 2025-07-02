# PrivateBox Ansible Roles

This directory contains all the Ansible roles used in the PrivateBox project. Each role is designed to be modular, reusable, and follows Ansible best practices.

## Available Roles

### Core Infrastructure
- **common**: Basic system configuration, users, packages, SSH, and time synchronization
- **proxmox**: Proxmox VE management - VM/container provisioning and configuration
- **security_hardening**: Comprehensive security hardening for Linux systems

### Network Services
- **opnsense**: OPNsense firewall deployment and configuration
- **adguard_home**: AdGuard Home DNS filtering service
- **unbound_dns**: Unbound recursive DNS resolver

### Management Services
- **portainer**: Docker container management platform with web UI
- **semaphore**: Modern web UI for Ansible automation

### Privacy Services (Planned)
- **wireguard**: WireGuard VPN server
- **openvpn**: OpenVPN server (alternative to WireGuard)
- **tor**: Tor proxy service

## Role Structure

Each role follows the standard Ansible role structure:

```
role_name/
├── defaults/       # Default variables
├── files/         # Static files
├── handlers/      # Handler definitions
├── meta/          # Role metadata and dependencies
├── tasks/         # Task definitions
├── templates/     # Jinja2 templates
└── vars/          # Role variables (higher priority than defaults)
```

## Using Roles

### In Playbooks

```yaml
- name: Deploy management services
  hosts: management_services
  roles:
    - common
    - portainer
    - semaphore
```

### With Tags

Most roles support tags for selective execution:

```bash
ansible-playbook site.yml --tags "portainer,portainer-deploy"
```

### Role Dependencies

Some roles depend on others. These dependencies are defined in the role's `meta/main.yml` file.

## Role Variables

Each role has documented default variables in `defaults/main.yml`. Override these in:
- Group variables: `inventories/<env>/group_vars/`
- Host variables: `inventories/<env>/host_vars/`
- Playbook variables
- Command line with `-e`

## Security Considerations

- **Vault**: Sensitive variables should be stored in Ansible Vault
- **Permissions**: File permissions are strictly controlled
- **Validation**: Each role includes validation tasks
- **Idempotency**: All roles are designed to be safely re-run

## Development Guidelines

When creating or modifying roles:

1. **Follow naming conventions**: Use lowercase with underscores
2. **Document variables**: Add descriptions in defaults/main.yml
3. **Use handlers**: For service restarts and reloads
4. **Add tags**: For granular execution control
5. **Test idempotency**: Ensure roles can be run multiple times safely
6. **Include validation**: Check prerequisites before making changes

## Testing

To test a role individually:

```bash
ansible-playbook -i inventories/development/hosts.yml test-role.yml -e "role_name=portainer"
```

Where test-role.yml:
```yaml
- hosts: appropriate_group
  roles:
    - "{{ role_name }}"
```

## Contributing

1. Create feature branch
2. Develop and test role
3. Update documentation
4. Submit pull request

## License

All roles are licensed under the MIT License unless otherwise specified.