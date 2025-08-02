# Work Log

Track active work: bugs, tasks, investigations, ideas. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Keep recent items at top. Move completed items to CHANGELOG.md.

---

## Active Work

- [Investigation] Research OPNsense VM deployment methods (starting - need template approach)
- [Task] Implement Ansible Vault for password management (pending - critical for v1)
- [Task] Deploy OPNsense VM with VLAN configuration (pending - critical for v1)
- [Task] Update service IPs to match VLAN design 10.10.20.x (pending - critical)
- [Bug] DNS config playbook missing auth headers (pending - causes 403 errors)
- [Bug] Caddy proxy returns 503 for AdGuard/Portainer backends (pending - config issue)
- [Bug] Port binding inconsistency - some services bind to IP, others to 0.0.0.0 (pending)
- [Task] Configure Caddy with Let's Encrypt SSL (pending - needed for proper access)
- [Task] Create internal DNS entries *.privatebox.local (pending)
- [Task] Write update playbooks for all services (pending)
- [Docs] Write basic user documentation (pending)