# Unbound DNS Role

This Ansible role deploys and configures Unbound as a recursive DNS resolver with DNSSEC validation.

## Features

- Full recursive DNS resolver (no forwarding required)
- DNSSEC validation enabled by default
- Optimized caching for performance
- Security hardening options
- Privacy protection features
- Integration-ready for AdGuard Home

## Requirements

- Ansible 2.9+
- SystemD-based Linux distribution

## Role Variables

Key variables (see `defaults/main.yml` for complete list):

```yaml
# Network configuration
unbound_interfaces:
  - "127.0.0.1"
  - "::1"
unbound_port: 5353  # Non-standard to work with AdGuard

# Performance tuning
unbound_num_threads: 4
unbound_msg_cache_size: "64m"
unbound_rrset_cache_size: "128m"

# Security features
unbound_hide_identity: true
unbound_hide_version: true
unbound_qname_minimisation: true
unbound_harden_glue: true
```

## Dependencies

None

## Example Playbook

```yaml
- hosts: dns_servers
  become: yes
  roles:
    - role: unbound_dns
      vars:
        unbound_num_threads: 2  # For smaller systems
```

## DNS Architecture

When used with AdGuard Home:
```
Client -> AdGuard Home (port 53) -> Unbound (port 5353) -> Root DNS servers
             |                           |
             v                           v
         Filtering                   DNSSEC validation
         Ad blocking                 Caching
         Statistics                  Privacy
```

## Testing

After deployment, test with:
```bash
# Basic resolution
dig @localhost -p 5353 example.com

# DNSSEC validation
dig @localhost -p 5353 dnssec-failed.org +dnssec
```

## License

MIT