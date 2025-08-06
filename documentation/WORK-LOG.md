# Work Log

Track active work organized by priority. Update via `/track`.
Format: `- [Category] Description (status/notes)`
Move completed items to CHANGELOG.md. New items go to Uncategorized for triage.

---

## Critical (P1) - v1 Blockers

- [Discovery] Proxmox second NIC (enp1s0) requires manual activation - `ip link set enp1s0 up` (CRITICAL - affects network design)
- [Investigation] Research OPNsense VM deployment methods (completed - see network-migration-plan.md)
- [Task] Deploy OPNsense VM with VLAN configuration (pending - see documentation/network-architecture/vlan-design.md) 
- [Task] Update service IPs to match VLAN design 10.10.20.x (pending - see documentation/network-architecture/vlan-design.md)

## Important (P2) - Should Have

- [Task] Create internal DNS entries *.privatebox.local (pending)
- [Task] Write update playbooks for all services (pending)
- [Bug] DNS config playbook missing auth headers (pending - causes 403 errors)

## Nice to Have (P3)

- [Bug] Port binding inconsistency - some services bind to IP, others to 0.0.0.0 (pending)
- [Docs] Write basic user documentation (pending)
- [Task] Update playbooks to use ServicePasswords environment (pending - low priority)

## Uncategorized - Needs Triage

- [Bug] enp1s0 not configured in /etc/network/interfaces - stays down after reboot (needs fix)
- [Task] Create bootstrap script to ensure both NICs are active on Proxmox