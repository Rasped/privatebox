# AdGuard Home Role

This Ansible role deploys AdGuard Home as a containerized DNS filtering service using Podman.

## Features

- Container-based deployment using Podman
- Automatic initial configuration via API
- Integration with Unbound DNS as upstream resolver
- Pre-configured blocklists for ads, malware, and tracking
- DNSSEC support through Unbound
- Web-based management interface
- Configurable DNS caching and performance settings

## Requirements

- Ansible 2.9+
- Podman installed on target hosts
- Python modules: `requests` (for API configuration)

## Role Variables

Key variables (see `defaults/main.yml` for complete list):

```yaml
# Container settings
adguard_container_name: adguard-home
adguard_container_image: adguard/adguardhome:latest

# Network configuration
adguard_web_port: 3000
adguard_dns_port: 53

# Upstream DNS (Unbound)
adguard_upstream_dns:
  - "127.0.0.1:5353"
  - "[::1]:5353"

# Admin credentials
adguard_admin_username: admin
adguard_admin_password: changeme  # Override in vault!

# Default blocklists
adguard_blocklists:
  - name: "AdGuard DNS filter"
    url: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
    enabled: true
```

## Dependencies

None required, but works best when deployed alongside the `unbound_dns` role.

## Example Playbook

```yaml
- hosts: dns_servers
  become: yes
  roles:
    - role: unbound_dns
    - role: adguard_home
      vars:
        adguard_admin_password: "{{ vault_adguard_password }}"
```

## Integration with Unbound

This role is configured to use Unbound DNS as its upstream resolver by default. Ensure Unbound is:
1. Installed and running on the same host
2. Configured to listen on port 5353
3. Accessible from localhost

## License

MIT