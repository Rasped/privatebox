# Work Log

Track active work organized by priority. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Move completed items to CHANGELOG.md. New items go to Uncategorized for triage.

---

## Critical (P1) - v1 Blockers

- [Investigation] Research OPNsense VM deployment methods (starting - need template approach)
- [Task] Streamline password generation and setting, start with config file (pending)
- [Task] Deploy OPNsense VM with VLAN configuration (pending) 
- [Task] Update service IPs to match VLAN design 10.10.20.x (pending)

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