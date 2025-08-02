# Work Log

Track active work organized by priority. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Move completed items to CHANGELOG.md. New items go to Uncategorized for triage.

---

## Critical (P1) - v1 Blockers

- [Investigation] Research OPNsense VM deployment methods (starting - need template approach)
- [Task] Integrate config-based installation into bootstrap scripts (in progress - see documentation/features/config-based-installation/config-design.md)
  - Sub-task: Update create-ubuntu-vm.sh to use generated passwords (pending)
  - Sub-task: Update common.sh to use new password generator (pending)
  - Sub-task: Test full bootstrap with new config approach (pending)
  - [Bug] Generated IPs (CONTAINER_HOST_IP, CADDY_HOST_IP, OPNSENSE_IP) not being used - VM uses SERVER_IP instead
  - [Bug] Generated SERVICES_PASSWORD not being used - VM still created with hardcoded Changeme123
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

## Uncategorized - Needs Triage

<!-- New items go here until prioritized -->