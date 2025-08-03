# Work Log

Track active work organized by priority. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Move completed items to CHANGELOG.md. New items go to Uncategorized for triage.

---

## Critical (P1) - v1 Blockers

- [Bug] Alpine VM deployment uses hardcoded password instead of ADMIN_PASSWORD from environment (RESOLVED - two-stage deployment)
- [Bug] Alpine VM inventory creation fails with HTTP 400 - Ansible uri module converts YAML to JSON, escaping newlines as \n literals. Semaphore API expects inventory field with actual newlines. Manual creation via UI works. Need to send raw YAML string without JSON escaping (RESOLVED - using curl directly)
- [Bug] Alpine VM SSH key architecture broken - Removed Proxmox SSH access but playbook requires it to retrieve VM's generated key. Password auth fails with "Permission denied" even though cloud-init sets lock_passwd: false and ssh_pwauth: true. Alpine cloud image SSH config not accepting our modifications. Tried sed commands and rc-service restart but still failing (ACTIVE INVESTIGATION - self-registration script ready but can't SSH to deploy it)
- [Investigation] Research OPNsense VM deployment methods (starting - need template approach)
- [Task] Deploy OPNsense VM with VLAN configuration (pending - see documentation/network-architecture/vlan-design.md) 
- [Task] Update service IPs to match VLAN design 10.10.20.x (pending - see documentation/network-architecture/vlan-design.md)

## Important (P2) - Should Have

- [Task] Configure Caddy with Let's Encrypt SSL (pending)
- [Task] Create internal DNS entries *.privatebox.local (pending)
- [Task] Write update playbooks for all services (pending)
- [Bug] DNS config playbook missing auth headers (pending - causes 403 errors)
- [Bug] Caddy proxy returns 503 for AdGuard/Portainer backends (pending)

## Nice to Have (P3)

- [Bug] Port binding inconsistency - some services bind to IP, others to 0.0.0.0 (pending)
- [Docs] Write basic user documentation (pending)
- [Task] Update playbooks to use ServicePasswords environment (pending - low priority)

## Uncategorized - Needs Triage