# Work Log

Track active work organized by priority. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Move completed items to CHANGELOG.md. New items go to Uncategorized for triage.

---

## Critical (P1) - v1 Blockers

- [Investigation] Research OPNsense VM deployment methods (starting - need template approach)
- [Task] Integrate config-based installation into bootstrap scripts (mostly complete - see documentation/features/config-based-installation/config-design.md)
  - Sub-task: Test full bootstrap with new config approach (pending)
  - [Bug] VM creates with different password than config-manager generated (pending - password regeneration issue)
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

- [Bug] Password displayed during VM creation differs from config-manager generated password (found today)
- [Note] SERVICES_PASSWORD purpose clarified - used for Semaphore admin login
- [Note] VM now uses predetermined IPs (.20, .21, .47) instead of searching for available IPs